import ConclaveCore
import SwiftUI

/// The Opponents tab: the decks played against, most recent first, with the record against each.
/// Tiles over the first opponent's art, like the Decks tab.
struct OpponentsView: View {
    let device: Device
    @Environment(AppModel.self) private var model
    @State private var path: [String] = ["opponent", "edit-opponent"].contains(AppModel.startScreen)
        ? [AppModel.demo?.opponents.first?.id].compactMap { $0 } : []

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let opponents = model.library?.opponents, !opponents.isEmpty {
                    TileGrid(backdrop: opponents.first?.commanders.first) {
                        ForEach(opponents) { opponent in
                            NavigationLink(value: opponent.id) { OpponentTile(opponent: opponent) }
                                .buttonStyle(.plain)
                        }
                    }
                    .refreshable { await model.refresh() }
                    // the commanders' art in one request
                    .task(id: opponents.count) { await model.cards.prefetch(opponents.flatMap(\.commanders)) }
                } else {
                    LibraryPlaceholder(empty: ("No Opponents Yet", "person.2", "Decks you played against show up here after a game."))
                }
            }
            .navigationTitle("Opponents")
            .navigationDestination(for: String.self) { id in
                if let opponent = model.library?.opponents.first(where: { $0.id == id }) {
                    OpponentView(opponent: opponent)
                } else {
                    ContentUnavailableView("Opponent Removed", systemImage: "person.2", description: Text("It was deleted on your PC."))
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { SettingsButton(device: device) }
                if model.inDemo {
                    ToolbarItem(placement: .topBarLeading) { DemoBadge(device: device) }
                }
            }
        }
        .outboxStatus()
    }
}

/// An opponent's tile: the commander's art, the deck's name, who plays it and your record against it.
struct OpponentTile: View {
    let opponent: Opponent

    private var commanders: String { opponent.commanders.joined(separator: " + ") }

    var body: some View {
        ArtTile(art: opponent.commanders.first ?? "", title: opponent.title,
                  subtitle: opponent.title == commanders ? nil : commanders) {
            ColorPips(colors: opponent.colors ?? "")
            if let player = opponent.player, !player.isEmpty { Text(player) }
            if opponent.record.games > 0 {
                // the person's own result against this deck
                Text(recordText(wins: opponent.record.wins, losses: opponent.record.losses, draws: opponent.record.draws))
                    .monospacedDigit()
                    .accessibilityLabel("You won \(opponent.record.wins), lost \(opponent.record.losses)")
            }
        }
    }
}

/// One opponent: what the deck does, notes from earlier games, and how each of the person's decks did.
/// "Edit" changes its name, player and bracket; the tag chips and "Add Note" save at once.
struct OpponentView: View {
    let opponent: Opponent
    @Environment(AppModel.self) private var model

    /// The commander whose card sheet is open.
    @State private var shownCard: DeckView.ShownCard?
    @State private var editing = AppModel.startScreen == "edit-opponent"
    @State private var addingNote = false

    var body: some View {
        List {
            header
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

            if !opponent.record.perDeck.isEmpty {
                Section {
                    ForEach(opponent.record.perDeck, id: \.name) { deck in
                        LabeledContent(deck.name, value: recordText(wins: deck.wins, losses: deck.losses, draws: 0))
                            .materialRow()
                    }
                } header: {
                    SectionTitle("Your Decks Against It")
                }
            }

            if let tags = model.library?.shownOptions.tags, !tags.isEmpty {
                Section {
                    // a tap saves at once, with "Undo" in the toast, like the PWA's tag chips
                    ChoiceChips(title: "Tap to change", choices: tags, picked: opponent.tags) { tag in
                        Task { await model.save("opponent.update", OpponentEdit.toggle(tag, on: opponent)) }
                    }
                    .materialRow()
                } header: {
                    SectionTitle("What It Does")
                }
            }

            Section {
                Button {
                    addingNote = true
                } label: {
                    Label("Add Note", systemImage: "plus")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(.rect)
                }
                .materialRow()
                ForEach(opponent.notes) { note in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(note.text)
                        if let at = ReadModel.date(note.at) {
                            Text(at, format: .dateTime.day().month().year())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .materialRow()
                }
            } header: {
                SectionTitle("Notes")
            }
        }
        .artList(over: opponent.commanders.first ?? "")
        .navigationTitle(opponent.title)
        .navigationBarTitleDisplayMode(.inline) // the header shows the name big
        .refreshable { await model.refresh() }
        .sheet(item: $shownCard) { shown in CardSheet(name: shown.name, copies: []) }
        .sheet(isPresented: $editing) { EditOpponentView(opponent: opponent) }
        .sheet(isPresented: $addingNote) { AddNoteView(opponent: opponent) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button("Edit") { editing = true } }
        }
    }

    /// True when the opponent has no name of its own, only its single commander's.
    private var namedAfterCommander: Bool {
        opponent.commanders.count == 1 && opponent.title == opponent.commanders[0]
    }

    /// The name, the commanders to tap, who plays it, what it does and your record as panels.
    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            if namedAfterCommander, let commander = opponent.commanders.first {
                Button {
                    shownCard = DeckView.ShownCard(name: commander)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(opponent.title)
                        Image(systemName: "chevron.right")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .font(.largeTitle.bold())
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Shows the card")
            } else {
                Text(opponent.title)
                    .font(.largeTitle.bold())
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }
            // the commanders to tap; left out when the name is just the commander (most opponents), and the title is the button
            VStack(alignment: .leading, spacing: 4) {
                ForEach(namedAfterCommander ? [] : opponent.commanders, id: \.self) { commander in
                    Button {
                        shownCard = DeckView.ShownCard(name: commander)
                    } label: {
                        HStack(spacing: 4) {
                            Text(commander)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .font(.headline)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Shows the card")
                }
            }
            HStack(spacing: 8) {
                ColorPips(colors: opponent.colors ?? "")
                if let bracket = opponent.bracket { Chip.bracket(bracket) }
                if let player = opponent.player, !player.isEmpty {
                    Text("Played by \(player)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 8) {
                StatPill(label: "Games", value: "\(opponent.record.games)")
                StatPill(label: "Won – lost", value: opponent.record.games == 0 ? "–"
                         : recordText(wins: opponent.record.wins, losses: opponent.record.losses, draws: opponent.record.draws))
            }
            .fixedSize(horizontal: false, vertical: true) // the panels share the tallest one's height
            if let last = ReadModel.date(opponent.record.last) {
                Text("Last played \(last, format: .relative(presentation: .named))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}
