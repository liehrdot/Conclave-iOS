import ConclaveCore
import SwiftUI

/// The Cards tab, like the PWA's Karten tab: "Name" finds any card by its English or German name,
/// straight from Scryfall (before typing, the cards opened last); "Describe" asks the sync server to
/// turn a description into a search (`DescribeSearch`). A tap opens the card sheet.
struct CardsView: View {
    let device: Device
    @Environment(AppModel.self) private var model
    /// Remembered across launches (not for screenshots, which pick their own).
    @State private var mode: Mode = AppModel.startScreen.map { $0 == "describe" ? .describe : .name }
        ?? Mode(rawValue: UserDefaults.standard.string(forKey: "cardMode") ?? "") ?? .name
    @State private var query = AppModel.startScreen == "cards" ? "Sol" : ""
    @State private var hits: [NameHit] = []
    @State private var searched = ""
    @State private var problem: String?
    @State private var shown: DeckView.ShownCard?
    /// The cards opened last, newest first, one name per line (`AppStorage` keeps strings, not lists).
    @AppStorage("recentCards") private var recentText = ""

    private static let recentMax = 12
    private var recent: [String] { recentText.split(separator: "\n").map(String.init) }
    private var typed: String { query.trimmingCharacters(in: .whitespaces) }

    enum Mode: String { case name, describe }

    var body: some View {
        NavigationStack {
            Group {
                switch mode {
                case .name: byName
                case .describe: DescribeSearch()
                }
            }
            .navigationTitle("Cards")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: mode) {
                if AppModel.startScreen == nil { UserDefaults.standard.set(mode.rawValue, forKey: "cardMode") }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Search by", selection: $mode) {
                        Text("Name").tag(Mode.name)
                        Text("Describe").tag(Mode.describe)
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
                ToolbarItem(placement: .topBarTrailing) { SettingsButton(device: device) }
                if model.inDemo {
                    ToolbarItem(placement: .topBarLeading) { DemoBadge(device: device) }
                }
            }
        }
    }

    private var byName: some View {
        List {
            if typed.isEmpty {
                if !recent.isEmpty {
                    Section {
                        ForEach(recent, id: \.self) { name in row(name: name, subtitle: nil, type: nil) }
                    } header: {
                        HStack {
                            GlassHeader("Recent")
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
            }
        }
        .glassList(over: hits.first?.name ?? recent.first ?? "")
        .overlay { placeholder }
        .searchable(text: $query, prompt: "Card name, English or German")
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .task(id: typed) { await search() }
        .sheet(item: $shown) { shown in CardSheet(name: shown.name, copies: []) }
    }

    /// What shows instead of a list: a hint before the first search, "no cards", or why it failed.
    @ViewBuilder private var placeholder: some View {
        if let problem, !typed.isEmpty {
            ContentUnavailableView {
                Label("Can't Search", systemImage: "wifi.exclamationmark")
            } description: {
                Text(problem)
            } actions: {
                Button("Try Again") { Task { await search(now: true) } }
            }
        } else if typed.isEmpty, recent.isEmpty {
            ContentUnavailableView("Search Cards", systemImage: "magnifyingglass",
                                   description: Text("Type a card's name, in English or German."))
        } else if !typed.isEmpty, searched == typed, hits.isEmpty {
            ContentUnavailableView.search(text: typed)
        }
    }

    private func row(name: String, subtitle: String?, type: String?, title: String? = nil) -> some View {
        SearchRow(name: name, title: title, subtitle: subtitle, type: type) { open(name) }
    }

    /// Searches once typing paused (the task restarts on every key, so only the last one runs).
    private func search(now: Bool = false) async {
        let text = typed
        guard !text.isEmpty else {
            hits = []
            problem = nil
            return
        }
        if !now {
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
        }
        do {
            let found = try await model.cards.scryfall.find(name: text)
            guard text == typed else { return }
            await model.cards.remember(found.compactMap(\.card))
            hits = found
            problem = nil
        } catch is CancellationError {
            return
        } catch {
            guard text == typed else { return }
            problem = (error as? CardError) == .offline
                ? "No connection to Scryfall. Cards you opened before still show."
                : "Scryfall didn't answer. Try again in a moment."
        }
        searched = text
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
                VStack(alignment: .leading, spacing: 2) {
                    Text(title ?? name).foregroundStyle(.primary)
                    if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(.secondary) }
                    if let type, !type.isEmpty { Text(type).font(.caption).foregroundStyle(.secondary) }
                }
                .lineLimit(1)
                Spacer(minLength: 0)
            }
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .glassRow()
    }
}
