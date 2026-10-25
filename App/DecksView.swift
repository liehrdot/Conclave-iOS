import ConclaveCore
import SwiftUI

/// The Decks tab: pinned decks first, paused ones last, in the read model's order (the PC's).
struct DecksView: View {
    let device: Device
    @Environment(AppModel.self) private var model
    @State private var path: [String] = ["deck", "rule0", "card"].contains(AppModel.startScreen)
        ? [AppModel.demo?.decks.first?.slug].compactMap { $0 } : []

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let decks = model.library?.decks, !decks.isEmpty {
                    List {
                        section("Pinned", decks.filter { $0.pinned && !$0.shelved })
                        section("Decks", decks.filter { !$0.pinned && !$0.shelved })
                        section("Paused", decks.filter(\.shelved))
                    }
                    .refreshable { await model.refresh() }
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
            }
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ decks: [Deck]) -> some View {
        if !decks.isEmpty {
            Section(title) {
                ForEach(decks) { deck in
                    NavigationLink(value: deck.slug) { DeckRow(deck: deck) }
                }
            }
        }
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
    @State private var showingRule0 = AppModel.startScreen == "rule0"
    /// The card whose sheet is open; the screenshot opens the demo deck's foil.
    @State private var shownCard: ShownCard? = AppModel.startScreen == "card" ? ShownCard(name: "Birds of Paradise") : nil

    var body: some View {
        List {
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

            ForEach(categories) { category in
                Section("\(category.name) · \(category.count)") {
                    ForEach(category.cards, id: \.self) { row($0) }
                }
            }

            if !deck.maybe.isEmpty {
                Section("Maybe") {
                    ForEach(deck.maybe, id: \.self) { row($0) }
                }
            }
        }
        .navigationTitle(deck.name)
        .refreshable { await model.refresh() }
        .sheet(isPresented: $showingRule0) { Rule0View(deck: deck) }
        .sheet(item: $shownCard) { shown in
            CardSheet(name: shown.name, copies: model.library?.copies(of: shown.name, in: deck) ?? [])
        }
        // the deck's cards in one request, so the card view opens at once and works offline later
        .task(id: deck.slug) { await model.cards.prefetch((deck.cards + deck.maybe).map(\.name)) }
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
        for card in deck.cards {
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

    var body: some View {
        HStack {
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
