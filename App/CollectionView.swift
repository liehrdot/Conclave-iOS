import ConclaveCore
import SwiftUI

/// The Collection tab: the cards from the PC's collection, one row per card, searchable and filtered by
/// original, proxy or foil, with the totals on top. A card opens its own screen with each printing and
/// place. Mirrors the PWA's Sammlung tab (`collection.js`).
struct CollectionView: View {
    let device: Device
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @AppStorage("collectionFilter") private var filter: CollectionFilter = .all
    @State private var path: [String] = AppModel.startScreen == "collection-card" ? ["Birds of Paradise"] : []
    @State private var adding = false

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let library = model.library, !library.collection.isEmpty {
                    list(library)
                } else {
                    LibraryPlaceholder(empty: ("No Cards Yet", "books.vertical",
                                               "Your collection from the PC shows up here once it has cards."))
                }
            }
            .navigationTitle("Collection")
            .navigationDestination(for: String.self) { name in CollectionCardView(name: name) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add a Card", systemImage: "plus") { adding = true }
                }
                ToolbarItem(placement: .topBarTrailing) { SettingsButton(device: device) }
                if model.inDemo {
                    ToolbarItem(placement: .topBarLeading) { DemoBadge(device: device) }
                }
            }
        }
        .sheet(isPresented: $adding) { AddByNameView() }
        .outboxStatus()
    }

    private func list(_ library: ReadModel) -> some View {
        let groups = library.collectionGroups(matching: query, filter: filter)
        return List {
            Section {
                header(library.collectionTotals)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            Section {
                ForEach(groups) { group in
                    NavigationLink(value: group.name) { CollectionRow(group: group, library: library) }
                        .materialRow()
                }
            }
            if groups.isEmpty {
                // the search and filter stay on screen, so they can be changed right here
                ContentUnavailableView(query.isEmpty ? "Nothing Here" : "No Matches", systemImage: "magnifyingglass",
                                       description: Text(query.isEmpty ? "No card fits this filter." : "No card fits “\(query)”."))
                    .listRowBackground(Color.clear)
            }
        }
        .artList(over: library.collection.first?.name ?? "")
        .searchable(text: $query, prompt: "Name, set or place")
        .refreshable { await model.refresh() }
    }

    /// The totals as panels, and the filter.
    private func header(_ totals: CollectionTotals) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            AdaptiveStack {
                StatPill(label: totals.cards == 1 ? "Card" : "Cards", value: totals.cards.formatted())
                StatPill(label: "Original", value: totals.originals.formatted())
                StatPill(label: "Proxy", value: totals.proxies.formatted())
                StatPill(label: "Value", value: totals.value.formatted(
                    .currency(code: "EUR").precision(.fractionLength(totals.value >= 1000 ? 0 : 2))))
            }
            .fixedSize(horizontal: false, vertical: true) // the panels share the tallest one's height
            Picker("Show", selection: $filter) {
                ForEach(CollectionFilter.allCases, id: \.self) { Text($0.title) }
            }
            .pickerStyle(.segmented)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

extension CollectionFilter {
    var title: String {
        switch self {
        case .all: "All"
        case .original: "Original"
        case .proxy: "Proxy"
        case .foil: "Foil"
        }
    }
}

/// One card of the collection: the picture of its printing, the name, what kind of copies and where, how many.
private struct CollectionRow: View {
    let group: CollectionGroup
    let library: ReadModel

    var body: some View {
        HStack(spacing: 12) {
            CardImage(url: group.entries.lazy.compactMap { $0.imageURL(.small) }.first)
                .frame(width: 36, height: 50)
                .clipShape(.rect(cornerRadius: 3))
            VStack(alignment: .leading, spacing: 2) {
                Text(group.name)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text("\(group.copies)×")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .accessibilityLabel(group.copies == 1 ? "1 copy" : "\(group.copies) copies")
        }
        .accessibilityElement(children: .combine)
    }

    /// One entry: its printing and kind and place; several: how many and what kind.
    private var subtitle: String {
        if group.entries.count == 1, let entry = group.entries.first {
            return entry.facts(place: library.placeName(of: entry)).joined(separator: " · ")
        }
        let proxies = group.entries.filter(\.proxy).reduce(0) { $0 + $1.qty }
        let foils = group.entries.filter(\.foil).reduce(0) { $0 + $1.qty }
        let kinds = [proxies > 0 ? "\(proxies) proxy" : nil, foils > 0 ? "\(foils) foil" : nil].compactMap { $0 }
        return (["\(group.entries.count) entries"] + (kinds.isEmpty ? ["various printings"] : kinds)).joined(separator: " · ")
    }
}

extension CollectionEntry {
    /// "C21 #263 · Proxy · Foil · DE · Binder": the short line for a printing, like the PWA's `printLine()`.
    func facts(place: String) -> [String] {
        let printing = set.map { "\($0.uppercased())\(collectorNumber.map { " #\($0)" } ?? "")" }
        return [printing, proxy ? "Proxy" : nil, foil ? "Foil" : nil, lang == "en" ? nil : lang.uppercased(),
                place.isEmpty ? nil : place].compactMap { $0 }
    }

    /// The language's name in the phone's language ("German").
    var languageName: String { Locale.current.localizedString(forLanguageCode: lang) ?? lang.uppercased() }
}

/// One card's entries: each printing and place with its copies, original or proxy, foil and place. Every
/// change saves at once with "Undo" in the toast; the number of copies is sent once the taps pause.
/// Mirrors `entrySheet()` in the PWA's `collection.js`.
struct CollectionCardView: View {
    let name: String
    @Environment(AppModel.self) private var model
    @State private var shownCard: DeckView.ShownCard?
    @State private var adding = false

    private var entries: [CollectionEntry] { model.library?.collection.filter { $0.name == name } ?? [] }

    var body: some View {
        List {
            if entries.isEmpty {
                ContentUnavailableView("Not in Your Collection", systemImage: "books.vertical",
                                       description: Text("It was removed, here or on your PC."))
                    .listRowBackground(Color.clear)
            } else {
                picture
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                ForEach(entries) { entry in
                    EntrySection(entry: entry)
                }
            }
        }
        .artList(over: name)
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $shownCard) { shown in CardSheet(name: shown.name, copies: shownCopies, inDeck: false) }
        .sheet(isPresented: $adding) { AddToCollectionView(name: name) }
        .toolbar {
            // another printing, another place: a new entry
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add Another", systemImage: "plus") { adding = true }
            }
        }
    }

    /// The copies the card sheet shows: those with a known printing (their picture), then the rest.
    private var shownCopies: [CollectionEntry] {
        entries.filter { $0.imageURL() != nil } + entries.filter { $0.imageURL() == nil }
    }

    /// The first printing's picture; a tap opens the card sheet with these printings.
    private var picture: some View {
        Button {
            shownCard = DeckView.ShownCard(name: name)
        } label: {
            CardImage(url: shownCopies.first?.imageURL())
                .aspectRatio(63 / 88, contentMode: .fit)
                .clipShape(CardShape())
                .frame(maxWidth: 220)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityHint("Shows the card's text")
    }
}

/// One entry: its printing as the heading, then copies, original or proxy, foil, place and "Remove".
private struct EntrySection: View {
    let entry: CollectionEntry
    @Environment(AppModel.self) private var model
    /// The copies while the stepper is being tapped; sent once the taps pause.
    @State private var copies: Int?
    @State private var sending: Task<Void, Never>?

    /// How long the stepper waits for more taps before it saves (the PWA waits 700 ms too).
    private static let pause: Duration = .milliseconds(700)

    var body: some View {
        Section {
            if let facts {
                Text(facts)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .materialRow()
            }
            Stepper(value: Binding(get: { copies ?? entry.qty }, set: { change($0) }), in: 1...CollectionEdit.maxCopies) {
                LabeledContent("Copies", value: (copies ?? entry.qty).formatted())
            }
            .materialRow()
            Toggle("Proxy", isOn: Binding(get: { entry.proxy }, set: { save(CollectionEdit.proxy(entry, $0)) }))
                .materialRow()
            Toggle("Foil", isOn: Binding(get: { entry.foil }, set: { save(CollectionEdit.foil(entry, $0)) }))
                .materialRow()
            NavigationLink {
                PlacePicker(art: entry.name, place: entry.placeDeck?.isEmpty ?? true ? entry.place ?? "" : "", deck: entry.placeDeck ?? "") {
                    if let payload = CollectionEdit.move(entry, place: $0, deck: $1, decks: model.library?.decks ?? []) {
                        Task { await model.save("collection.update", payload) }
                    }
                }
            } label: {
                LabeledContent("Place", value: model.library.map { $0.placeName(of: entry) }.flatMap { $0.isEmpty ? nil : $0 } ?? "None")
            }
            .materialRow()
            Button("Remove from Collection", role: .destructive) {
                // no question first: the toast's "Undo" brings it back (HIG, Alerts)
                sending?.cancel()
                save(CollectionEdit.remove(entry))
            }
            .materialRow()
        } header: {
            SectionTitle(entry.setName ?? entry.set?.uppercased() ?? "No Printing")
        }
    }

    /// "C21 #263 · German · €1.20": the printing's number, its language and the price when it was added.
    private var facts: String? {
        let number = entry.set.map { "\($0.uppercased())\(entry.collectorNumber.map { " #\($0)" } ?? "")" }
        let price = entry.proxy ? nil : entry.priceEur.flatMap { Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX")) }
        let parts = [number, entry.languageName, price?.formatted(.currency(code: "EUR"))].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func change(_ qty: Int) {
        copies = qty
        sending?.cancel()
        sending = Task {
            try? await Task.sleep(for: Self.pause)
            guard !Task.isCancelled else { return }
            if let payload = CollectionEdit.quantity(entry, to: qty) { await model.save("collection.update", payload) }
            copies = nil
        }
    }

    private func save(_ payload: JSONValue?) {
        guard let payload else { return }
        Task { await model.save("collection.update", payload) }
    }
}

/// Where copies are: no place, one of the decks, a place already in use, or a new one typed in. `onPick`
/// gets the place text and the deck's slug ("" for none). Mirrors `placePage()` in the PWA's `scan.js`.
struct PlacePicker: View {
    /// The card whose art lies behind the list.
    let art: String
    /// The place now: a text or a deck's slug.
    let place: String
    let deck: String
    let onPick: (_ place: String, _ deck: String) -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    private var decks: [Deck] {
        (model.library?.decks ?? []).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var isDeckPlace: Bool { !deck.isEmpty }

    var body: some View {
        List {
            Section {
                TextField("New place, like Red Binder", text: $text)
                    .submitLabel(.done)
                    .onSubmit { pick(place: text) }
                    .materialRow()
                Button("Use This Place") { pick(place: text) }
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                    .materialRow()
            }
            Section {
                row("No Place", picked: !isDeckPlace && place.isEmpty) { pick() }
            }
            if !decks.isEmpty {
                Section {
                    ForEach(decks) { deck in
                        row(deck.name, detail: deck.commanders.joined(separator: " + "), picked: self.deck == deck.slug) {
                            pick(deck: deck.slug)
                        }
                    }
                } header: {
                    SectionTitle("Decks")
                }
            }
            if let places = model.library?.knownPlaces, !places.isEmpty {
                Section {
                    ForEach(places, id: \.place) { known in
                        row(known.place, detail: known.cards == 1 ? "1 card" : "\(known.cards) cards",
                            picked: !isDeckPlace && place.lowercased() == known.place.lowercased()) {
                            pick(place: known.place)
                        }
                    }
                } header: {
                    SectionTitle("Your Places")
                }
            }
        }
        .artList(over: art)
        .navigationTitle("Place")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { text = place }
    }

    private func row(_ title: String, detail: String? = nil, picked: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(.primary)
                    if let detail, !detail.isEmpty {
                        Text(detail).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if picked {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .contentShape(.rect)
        }
        .accessibilityAddTraits(picked ? .isSelected : [])
        .materialRow()
    }

    private func pick(place: String = "", deck: String = "") {
        onPick(place, deck)
        dismiss()
    }
}
