import ConclaveCore
import SwiftUI

/// The Cards tab, like the PWA's Karten tab: "Name" finds any card by its English or German name,
/// straight from Scryfall (before typing, the cards opened last), narrowed by the filters (`CardFilter`:
/// what it does, colours, types; with a filter and no name, the most played cards that fit); "Describe"
/// asks the sync server to turn a description into a search (`DescribeSearch`). A tap opens the card sheet.
struct CardsView: View {
    let device: Device
    @Environment(AppModel.self) private var model
    /// Remembered across launches (not for screenshots, which pick their own).
    @State private var mode: Mode = AppModel.startScreen.map { $0 == "describe" ? .describe : .name }
        ?? Mode(rawValue: UserDefaults.standard.string(forKey: "cardMode") ?? "") ?? .name
    @State private var query = AppModel.startScreen == "cards" ? "Sol" : ""
    @State private var filter = AppModel.startScreen == "filters" ? CardFilter(role: "otag:ramp", colors: ["G"]) : CardFilter()
    @State private var filtering = false
    @State private var hits: [NameHit] = []
    /// The next page of a filtered search.
    @State private var next: Int?
    @State private var loadingMore = false
    @State private var searched: Search?
    @State private var problem: String?
    @State private var shown: DeckView.ShownCard?
    /// The cards opened last, newest first, one name per line (`AppStorage` keeps strings, not lists).
    @AppStorage("recentCards") private var recentText = ""

    private static let recentMax = 12
    private var recent: [String] { recentText.split(separator: "\n").map(String.init) }
    private var typed: String { query.trimmingCharacters(in: .whitespaces) }
    private var current: Search { Search(text: typed, filter: filter) }
    /// Nothing to search for: the recent cards show.
    private var idle: Bool { typed.isEmpty && filter.isEmpty }

    enum Mode: String { case name, describe }

    /// What a search ran for; a new one starts when either part changes.
    struct Search: Equatable {
        let text: String
        let filter: CardFilter
    }

    var body: some View {
        NavigationStack {
            Group {
                switch mode {
                case .name: byName
                case .describe: DescribeSearch()
                }
            }
            // no title: the Name | Describe switch says what the screen is, and a title would sit beside it
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: mode) {
                if AppModel.startScreen == nil { UserDefaults.standard.set(mode.rawValue, forKey: "cardMode") }
            }
            .toolbar {
                // leading, not centred: the trailing buttons differ per mode (Filters only for Name), and a
                // centred item moves sideways when they do
                ToolbarItem(placement: .topBarLeading) {
                    Picker("Search by", selection: $mode) {
                        Text("Name").tag(Mode.name)
                        Text("Describe").tag(Mode.describe)
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
                .sharedBackgroundVisibility(.hidden) // the switch is its own glass; iOS would add a second one
                ToolbarItem(placement: .topBarTrailing) { SettingsButton(device: device) }
                if mode == .name {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Filters", systemImage: filter.isEmpty ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill") {
                            filtering = true
                        }
                    }
                }
                if model.inDemo {
                    ToolbarItem(placement: .topBarLeading) { DemoBadge(device: device) }
                }
            }
        }
    }

    private var byName: some View {
        List {
            if !filter.isEmpty {
                Section {
                    FilterSummary(filter: filter, edit: { filtering = true }, clear: { withAnimation { filter = CardFilter() } })
                }
            }
            if idle {
                if !recent.isEmpty {
                    Section {
                        ForEach(recent, id: \.self) { name in row(name: name, subtitle: nil, type: nil) }
                    } header: {
                        HStack {
                            SectionTitle("Recent")
                            Spacer()
                            Button("Clear") { withAnimation { recentText = "" } }
                                .font(.subheadline)
                        }
                    }
                }
            } else {
                ForEach(hits) { hit in
                    // a German name that matched shows first, the English one under it
                    row(name: hit.name, subtitle: hit.german.map { _ in hit.name }, type: hit.type, title: hit.german)
                }
                if let next, searched == current {
                    Button("Show More") { Task { await more(page: next) } }
                        .disabled(loadingMore)
                        .materialRow()
                }
            }
        }
        .artList(over: hits.first?.name ?? recent.first ?? "")
        .overlay { placeholder }
        .searchable(text: $query, prompt: "Card name, English or German")
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .task(id: current) { await search() }
        .sheet(item: $shown) { shown in CardSheet(name: shown.name, copies: []) }
        .sheet(isPresented: $filtering) { FilterSheet(filter: $filter) }
    }

    /// What shows instead of a list: a hint before the first search, "no cards", or why it failed.
    @ViewBuilder private var placeholder: some View {
        if let problem, !idle {
            ContentUnavailableView {
                Label("Can't Search", systemImage: "wifi.exclamationmark")
            } description: {
                Text(problem)
            } actions: {
                Button("Try Again") { Task { await search(now: true) } }
            }
        } else if idle, recent.isEmpty {
            ContentUnavailableView("Search Cards", systemImage: "magnifyingglass",
                                   description: Text("Type a card's name, in English or German, or pick a filter."))
        } else if !idle, searched == current, hits.isEmpty {
            if typed.isEmpty {
                ContentUnavailableView("No Cards", systemImage: "line.3.horizontal.decrease",
                                       description: Text("No card fits all of these filters."))
            } else {
                ContentUnavailableView.search(text: typed)
            }
        }
    }

    private func row(name: String, subtitle: String?, type: String?, title: String? = nil) -> some View {
        SearchRow(name: name, title: title, subtitle: subtitle, type: type) { open(name) }
    }

    /// Searches once typing paused (the task restarts on every key, so only the last one runs). With a
    /// filter it is one Scryfall search, page by page; without, the name search.
    private func search(now: Bool = false) async {
        let wanted = current
        guard !idle else {
            hits = []
            next = nil
            problem = nil
            return
        }
        if !now {
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
        }
        do {
            if let query = wanted.filter.query(name: wanted.text) {
                let page = try await model.cards.scryfall.search(query, multilingual: true)
                guard wanted == current else { return }
                await model.cards.remember(page.cards)
                hits = page.cards.map(NameHit.init)
                next = page.next
            } else {
                let found = try await model.cards.scryfall.find(name: wanted.text)
                guard wanted == current else { return }
                await model.cards.remember(found.compactMap(\.card))
                hits = found
                next = nil
            }
            problem = nil
        } catch is CancellationError {
            return
        } catch {
            guard wanted == current else { return }
            problem = Self.message(for: error)
        }
        searched = wanted
    }

    /// The next page of a filtered search.
    private func more(page: Int) async {
        guard let query = current.filter.query(name: current.text) else { return }
        loadingMore = true
        defer { loadingMore = false }
        do {
            let found = try await model.cards.scryfall.search(query, page: page, multilingual: true)
            await model.cards.remember(found.cards)
            hits += found.cards.map(NameHit.init).filter { hit in !hits.contains { $0.name == hit.name } }
            next = found.next
        } catch {
            problem = Self.message(for: error)
        }
    }

    private static func message(for error: any Error) -> String {
        switch error as? CardError {
        case .offline: "No connection to Scryfall. Cards you opened before still show."
        case .badQuery: "Scryfall couldn't read this search. Try fewer filters."
        default: "Scryfall didn't answer. Try again in a moment."
        }
    }

    /// Opens the card sheet and puts the card at the top of the recent ones.
    private func open(_ name: String) {
        shown = DeckView.ShownCard(name: name)
        recentText = ([name] + recent.filter { $0 != name }).prefix(Self.recentMax).joined(separator: "\n")
    }
}

/// One card in a search's results: its art, its name (or the German one that matched, with the
/// English one under it) and its type line. The whole row is the button.
struct SearchRow: View {
    let name: String
    var title: String? = nil
    var subtitle: String? = nil
    var type: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                CardArt(name: name)
                    .frame(width: 52, height: 38)
                    .clipShape(.rect(cornerRadius: 6))
                // the name wraps instead of being cut off (HIG, Typography); the smaller lines keep to two
                VStack(alignment: .leading, spacing: 2) {
                    Text(title ?? name).foregroundStyle(.primary)
                    if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(2) }
                    if let type, !type.isEmpty { Text(type).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .materialRow()
    }
}

/// The filters in use, one line above the results: a tap changes them, the x clears them.
private struct FilterSummary: View {
    let filter: CardFilter
    let edit: () -> Void
    let clear: () -> Void

    private var text: String {
        var parts: [String] = []
        if let role = CardFilter.roles.first(where: { $0.key == filter.role }) { parts.append(role.label) }
        let colors = DescribeSearch.colorChoices.filter { filter.colors.contains($0.key) }.map(\.label)
        if !colors.isEmpty { parts.append(colors.formatted(.list(type: .or))) }
        let types = DescribeSearch.typeChoices.filter { filter.types.contains($0.key) }.map(\.label)
        if !types.isEmpty { parts.append(types.formatted(.list(type: .or))) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: edit) {
                Label(text, systemImage: "line.3.horizontal.decrease")
                    .foregroundStyle(Color.accentColor)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Changes the filters")
            Button("Clear Filters", systemImage: "xmark.circle.fill", action: clear)
                .labelStyle(.iconOnly)
                .foregroundStyle(.secondary)
                .frame(minWidth: 44, minHeight: 44)
                .buttonStyle(.plain)
        }
        .materialRow()
    }
}

/// "Filters": what the card does (one at a time), its colours and its types. Changes apply at once, so
/// the results behind the sheet follow along.
private struct FilterSheet: View {
    @Binding var filter: CardFilter
    @Environment(\.dismiss) private var dismiss

    private static let roleChoices = CardFilter.roles.map { Options.Choice(key: $0.key, label: $0.label) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ChoiceChips(title: "What it does", choices: Self.roleChoices, picked: filter.role.map { [$0] } ?? []) { key in
                        filter.role = filter.role == key ? nil : key
                    }
                    ChoiceChips(title: "Colors", choices: DescribeSearch.colorChoices, picked: filter.colors) { toggle($0, in: &filter.colors) }
                    ChoiceChips(title: "Card type", choices: DescribeSearch.typeChoices, picked: filter.types) { toggle($0, in: &filter.types) }
                } footer: {
                    Text("Only cards allowed in Commander, most played first. Colorless cards show only when Colorless is picked too.")
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear") { filter = CardFilter() }
                        .disabled(filter.isEmpty)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", role: .confirm) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func toggle(_ key: String, in list: inout [String]) {
        if let index = list.firstIndex(of: key) { list.remove(at: index) } else { list.append(key) }
    }
}
