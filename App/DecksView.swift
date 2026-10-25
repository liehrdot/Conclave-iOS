import ConclaveCore
import SwiftUI

/// The Decks tab: pinned decks first, paused ones last, in the read model's order (the PC's).
struct DecksView: View {
    let device: Device
    @Environment(AppModel.self) private var model
    @Environment(\.look) private var look
    @State private var path: [String] = ["deck", "rule0", "card"].contains(AppModel.startScreen)
        ? [AppModel.demo?.decks.first?.slug].compactMap { $0 } : []

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let decks = model.library?.decks, !decks.isEmpty {
                    Group {
                        switch look {
                        case .gallery, .glass:
                            DeckTiles(groups: groups(decks))
                        default:
                            List {
                                ForEach(groups(decks)) { group in
                                    Section {
                                        ForEach(group.decks) { deck in
                                            NavigationLink(value: deck.slug) {
                                                if look == .brand { BrandDeckRow(deck: deck) } else { DeckRow(deck: deck) }
                                            }
                                            .modifier(LookRow())
                                        }
                                    } header: {
                                        LookHeader(group.title)
                                    }
                                }
                            }
                            .modifier(LookList(commander: ""))
                        }
                    }
                    .refreshable { await model.refresh() }
                    // the commanders' art in one request
                    .task(id: decks.count) { await model.cards.prefetch(decks.flatMap(\.commanders)) }
                } else {
                    LibraryPlaceholder(empty: ("No Decks Yet", "rectangle.stack", "Decks you build on your PC show up here."))
                }
            }
            .navigationTitle("Decks")
            .navigationDestination(for: String.self) { slug in
                if let deck = model.library?.decks.first(where: { $0.slug == slug }) {
                    DeckView(deck: deck)
                } else {
                    ContentUnavailableView("Deck Removed", systemImage: "rectangle.stack", description: Text("It was deleted on your PC."))
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { SettingsButton(device: device) }
                if model.inDemo {
                    ToolbarItem(placement: .topBarLeading) { DemoBadge(device: device) }
                }
            }
        }
    }

    /// Pinned, the rest, paused; empty groups left out.
    private func groups(_ decks: [Deck]) -> [DeckGroup] {
        [
            DeckGroup(title: "Pinned", decks: decks.filter { $0.pinned && !$0.shelved }),
            DeckGroup(title: "Decks", decks: decks.filter { !$0.pinned && !$0.shelved }),
            DeckGroup(title: "Paused", decks: decks.filter(\.shelved)),
        ].filter { !$0.decks.isEmpty }
    }
}

struct DeckRow: View {
    let deck: Deck

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(deck.name)
                .font(.headline)
            Text(deck.commanders.joined(separator: " + "))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            HStack(spacing: 8) {
                ColorPips(colors: deck.colors)
                if let level = deck.shownLevel {
                    Text(level)
                }
                if deck.record.games > 0 {
                    Text(recordText(wins: deck.record.wins, losses: deck.record.losses, draws: deck.record.draws))
                        .monospacedDigit()
                        .accessibilityLabel("\(deck.record.wins) wins, \(deck.record.losses) losses")
                }
                if deck.legal == false {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Not legal")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

/// One deck: what it is, Rule 0, how it did, and its cards by category.
struct DeckView: View {
    let deck: Deck
    @Environment(AppModel.self) private var model
    @Environment(\.look) private var look
    @State private var showingRule0 = AppModel.startScreen == "rule0"
    /// The card whose sheet is open; the screenshot opens the demo deck's foil.
    @State private var shownCard: ShownCard? = AppModel.startScreen == "card" ? ShownCard(name: "Birds of Paradise") : nil
    /// What the search field filters the cards by; while it has text only matching cards show.
    @State private var query = ""

    var body: some View {
        List {
            if searching {
                if shownCards.isEmpty && shownMaybe.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            } else if look == .today {
                summary
            } else {
                DeckHeader(deck: deck, showCard: { shownCard = ShownCard(name: $0) }, showRule0: { showingRule0 = true })
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            ForEach(categories) { category in
                Section {
                    ForEach(category.cards, id: \.self) { row($0).modifier(LookRow()) }
                } header: {
                    LookHeader("\(category.name) · \(category.count)")
                }
            }

            if !shownMaybe.isEmpty {
                Section {
                    ForEach(shownMaybe, id: \.self) { row($0).modifier(LookRow()) }
                } header: {
                    LookHeader("Maybe")
                }
            }
        }
        .modifier(LookList(commander: deck.commanders.first ?? ""))
        .searchable(text: $query, prompt: "Cards in this deck")
        .navigationTitle(deck.name)
        .navigationBarTitleDisplayMode(look == .today ? .automatic : .inline)
        .refreshable { await model.refresh() }
        .sheet(isPresented: $showingRule0) { Rule0View(deck: deck) }
        .sheet(item: $shownCard) { shown in
            CardSheet(name: shown.name, copies: model.library?.copies(of: shown.name, in: deck) ?? [])
        }
        // the deck's cards in one request, so the card view opens at once and works offline later
        .task(id: deck.slug) { await model.cards.prefetch((deck.cards + deck.maybe).map(\.name)) }
    }

    private var searching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }
    private func matches(_ card: Deck.Card) -> Bool {
        !searching || card.name.localizedStandardContains(query.trimmingCharacters(in: .whitespaces))
    }
    private var shownCards: [Deck.Card] { deck.cards.filter(matches) }
    private var shownMaybe: [Deck.Card] { deck.maybe.filter(matches) }

    /// The commander, Rule 0 and the record: hidden while searching, so the matches come first.
    @ViewBuilder
    private var summary: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                // tap a commander for its card, like any card in the list
                ForEach(deck.commanders, id: \.self) { commander in
                    Button {
                        shownCard = ShownCard(name: commander)
                    } label: {
                        HStack(spacing: 4) {
                            Text(commander)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .buttonStyle(.plain)
                    .accessibilityHint("Shows the card")
                }
                HStack(spacing: 8) {
                    ColorPips(colors: deck.colors)
                    if let level = deck.shownLevel { Text(level) }
                    if deck.proxy { Text("Proxy") }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                if let description = deck.description, !description.isEmpty {
                    Text(description)
                        .font(.subheadline)
                }
                if deck.checking {
                    Label("Your PC checks the newest changes next time it syncs.", systemImage: "clock")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
            Button {
                showingRule0 = true
            } label: {
                Label("Rule 0", systemImage: "text.bubble")
            }
        }

        Section("Record") {
            if deck.record.games == 0 {
                Text("No games yet.")
                    .foregroundStyle(.secondary)
            } else {
                LabeledContent("Games", value: "\(deck.record.games)")
                LabeledContent("Won – lost", value: recordText(wins: deck.record.wins, losses: deck.record.losses, draws: deck.record.draws))
                if let last = ReadModel.date(deck.record.last) {
                    LabeledContent("Last played") { Text(last, format: .relative(presentation: .named)) }
                }
            }
            if let speed = deck.speed, let label = speed.shownLabel {
                LabeledContent("Speed", value: label)
            }
        }
    }

    private func row(_ card: Deck.Card) -> some View {
        Button {
            shownCard = ShownCard(name: card.name)
        } label: {
            CardRow(card: card, copies: model.library?.copies(of: card.name, in: deck) ?? [])
        }
        .foregroundStyle(.primary)
    }

    struct ShownCard: Identifiable {
        var id: String { name }
        let name: String
    }

    struct Category: Identifiable {
        var id: String { name }
        let name: String
        let count: Int
        let cards: [Deck.Card]
    }

    /// The cards grouped by category, in the order the categories first come up.
    private var categories: [Category] {
        var order: [String] = []
        var groups: [String: [Deck.Card]] = [:]
        for card in shownCards {
            let name = card.category.flatMap { $0.isEmpty ? nil : $0 } ?? "Other"
            if groups[name] == nil { order.append(name) }
            groups[name, default: []].append(card)
        }
        return order.map { name in
            let cards = groups[name] ?? []
            return Category(name: name, count: cards.reduce(0) { $0 + ($1.qty ?? 1) }, cards: cards)
        }
    }
}

/// A card in the deck list: its name, a tag when the copy in the deck is a foil or a proxy, the count.
struct CardRow: View {
    let card: Deck.Card
    /// The person's copies placed in this deck.
    let copies: [CollectionEntry]
    @Environment(\.look) private var look

    var body: some View {
        HStack {
            if look != .today {
                CardArt(name: card.name)
                    .frame(width: 44, height: 32)
                    .clipShape(.rect(cornerRadius: look == .brand ? 3 : 6))
            }
            Text(card.name)
            Spacer()
            if copies.contains(where: \.foil) {
                Tag(text: "Foil", tint: .purple).font(.caption)
            }
            if !copies.isEmpty, copies.allSatisfy(\.proxy) {
                Tag(text: "Proxy", tint: .orange).font(.caption)
            }
            if let qty = card.qty, qty > 1 {
                Text("×\(qty)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Rule 0 as a sheet: what to tell the table, rows worth mentioning marked, and the text to share.
struct Rule0View: View {
    let deck: Deck
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(deck.shownRule0.rows, id: \.self) { row in
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.label)
                        .font(.caption)
                        .foregroundStyle(row.flag ? Color.orange : Color.secondary)
                    Text(row.value)
                }
                .padding(.vertical, 2)
                .accessibilityElement(children: .combine)
                .accessibilityHint(row.flag ? "Worth mentioning at the table" : "")
                .listRowBackground(row.flag ? Color.orange.opacity(0.12) : nil)
            }
            .navigationTitle("Rule 0")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: deck.shownRule0.text)
                }
            }
        }
    }
}
