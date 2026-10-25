import ConclaveCore
import SwiftUI

/// The Opponents tab: the decks played against, most recent first, with the record against each.
struct OpponentsView: View {
    let device: Device
    @Environment(AppModel.self) private var model
    @State private var path: [String] = AppModel.startScreen == "opponent"
        ? [AppModel.demo?.opponents.first?.id].compactMap { $0 } : []

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let opponents = model.library?.opponents, !opponents.isEmpty {
                    List(opponents) { opponent in
                        NavigationLink(value: opponent.id) { OpponentRow(opponent: opponent) }
                    }
                    .refreshable { await model.refresh() }
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
            }
        }
    }
}

struct OpponentRow: View {
    let opponent: Opponent

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(opponent.title)
                .font(.headline)
            HStack(spacing: 8) {
                ColorPips(colors: opponent.colors ?? "")
                if let player = opponent.player, !player.isEmpty { Text(player) }
                if opponent.record.games > 0 {
                    // the person's own result against this deck
                    Text(recordText(wins: opponent.record.wins, losses: opponent.record.losses, draws: opponent.record.draws))
                        .monospacedDigit()
                        .accessibilityLabel("You won \(opponent.record.wins), lost \(opponent.record.losses)")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

/// One opponent: what the deck does, notes from earlier games, and how each of the person's decks did.
struct OpponentView: View {
    let opponent: Opponent
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    if opponent.title != opponent.commanders.joined(separator: " + ") {
                        Text(opponent.commanders.joined(separator: " + "))
                            .font(.headline)
                    }
                    HStack(spacing: 8) {
                        ColorPips(colors: opponent.colors ?? "")
                        if let player = opponent.player, !player.isEmpty { Text("Played by \(player)") }
                        if let bracket = opponent.bracket { Text("Bracket \(bracket)") }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                if !opponent.tags.isEmpty {
                    let tags = model.library?.shownOptions.tags ?? []
                    Text(opponent.tags.map { Options.label($0, in: tags) }.formatted(.list(type: .and)))
                }
            }

            Section("Your Record") {
                if opponent.record.games == 0 {
                    Text("No games yet.")
                        .foregroundStyle(.secondary)
                } else {
                    LabeledContent("Games", value: "\(opponent.record.games)")
                    LabeledContent("Won – lost", value: recordText(wins: opponent.record.wins, losses: opponent.record.losses, draws: opponent.record.draws))
                    ForEach(opponent.record.perDeck, id: \.name) { deck in
                        LabeledContent(deck.name, value: recordText(wins: deck.wins, losses: deck.losses, draws: 0))
                    }
                }
            }

            if !opponent.notes.isEmpty {
                Section("Notes") {
                    ForEach(opponent.notes) { note in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(note.text)
                            if let at = ReadModel.date(note.at) {
                                Text(at, format: .dateTime.day().month().year())
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(opponent.title)
        .refreshable { await model.refresh() }
    }
}
