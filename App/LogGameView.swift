import ConclaveCore
import SwiftUI

/// "Log a Game": the result first and big, then who sat at the table and the places, the rest under
/// "More Details". Saving puts a `game.add` in the outbox: the game shows up in the deck and opponent
/// screens at once and goes to the server when it can. Mirrors the PWA's game sheet (`forms.js`).
struct LogGameView: View {
    let deck: Deck
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var draft: GameDraft
    @State private var picking = false
    @State private var details = false
    @State private var saved = 0

    /// `library` = what the app shows now: the last game in it decides whether the same table sits again.
    init(deck: Deck, library: ReadModel?) {
        self.deck = deck
        var draft = GameDraft(deck: deck.slug, library: library ?? ReadModel())
        if AppModel.startScreen == "log-game" { Self.fillForScreenshot(&draft) }
        _draft = State(initialValue: draft)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ResultPicker(result: draft.result, labels: options.results) { draft.setResult($0) }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                Section {
                    ForEach(Array(draft.seats.enumerated()), id: \.element.id) { index, seat in
                        HStack(spacing: 12) {
                            CardArt(name: seat.commander)
                                .frame(width: 36, height: 36)
                                .clipShape(.circle)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(name(of: seat)).lineLimit(1)
                                if let player = opponent(of: seat)?.player, !player.isEmpty {
                                    Text(player).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .glassRow()
                        .swipeActions { Button("Remove", role: .destructive) { draft.removeSeat(at: index) } }
                    }
                    if draft.seats.count < GameDraft.maxOpponents {
                        Button("Add Opponent", systemImage: "plus") { picking = true }
                            .glassRow()
                    }
                } header: {
                    GlassHeader("Opponents")
                } footer: {
                    if draft.rematch { Text("The same table as your last game. Swipe to remove someone.") }
                }

                if !draft.seats.isEmpty {
                    Section {
                        PlaceRow(name: "You", art: deck.commanders.first ?? "", place: draft.place, of: draft.tableSize) {
                            draft.setPlace($0)
                        }
                        .glassRow()
                        ForEach(Array(draft.seats.enumerated()), id: \.element.id) { index, seat in
                            PlaceRow(name: name(of: seat), art: seat.commander, place: seat.place, of: draft.tableSize) {
                                draft.setPlace($0, seat: index)
                            }
                            .glassRow()
                        }
                    } header: {
                        GlassHeader("Places")
                    } footer: {
                        Text("Optional. Tap a place again to clear it.")
                    }
                }

                Section {
                    DisclosureGroup("More Details", isExpanded: $details) {
                        Picker("Last Turn", selection: $draft.turn) {
                            Text("Not Noted").tag(Int?.none)
                            ForEach(1...30, id: \.self) { Text("Turn \($0)").tag(Int?.some($0)) }
                        }
                        if !options.how.isEmpty {
                            ChoiceChips(title: "How It Ended", choices: options.how, picked: draft.how.map { [$0] } ?? []) { key in
                                draft.how = draft.how == key ? nil : key
                            }
                        }
                        if draft.result == "loss" || draft.result == "draw", !options.issues.isEmpty {
                            ChoiceChips(title: "What Went Wrong", choices: options.issues, picked: draft.issues) { key in
                                if let at = draft.issues.firstIndex(of: key) { draft.issues.remove(at: at) } else { draft.issues.append(key) }
                            }
                        }
                        TextField("Note", text: $draft.note, prompt: Text("What stood out?"), axis: .vertical)
                            .lineLimit(2...6)
                    }
                    .glassRow()
                }
            }
            .glassList(over: deck.commanders.first ?? "")
            .navigationTitle("Log a Game")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", role: .confirm) { save() }
                        .disabled(!draft.canSave)
                }
            }
            .sheet(isPresented: $picking) {
                OpponentPicker(taken: Set(draft.seats.compactMap(\.opponentID))) { draft.add($0) }
            }
            .sensoryFeedback(.success, trigger: saved)
        }
    }

    private var options: Options { model.library?.shownOptions ?? Options() }

    private func opponent(of seat: GameDraft.Seat) -> Opponent? {
        seat.opponentID.flatMap { id in model.library?.opponents.first { $0.id == id } }
    }

    private func name(of seat: GameDraft.Seat) -> String { opponent(of: seat)?.title ?? seat.commander }

    private func save() {
        guard let payload = draft.payload else { return }
        saved += 1
        Task { await model.save("game.add", payload) }
        dismiss()
    }

    /// What the CI screenshot shows: a lost game against two of the demo's opponents.
    private static func fillForScreenshot(_ draft: inout GameDraft) {
        draft.add(.init(opponentID: "o-atraxa", commander: "Atraxa, Praetors' Voice", colors: "WUBG"))
        draft.add(.init(opponentID: "o-krenko", commander: "Krenko, Mob Boss", colors: "R"))
        draft.setPlace(1, seat: 0)
        draft.setPlace(2)
    }
}

/// Won, Lost, Draw as three big buttons: the one answer every game needs.
private struct ResultPicker: View {
    let result: String?
    let labels: [String: String]
    let pick: (String) -> Void

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                button("win", fallback: "Won", symbol: "trophy")
                button("loss", fallback: "Lost", symbol: "xmark")
                button("draw", fallback: "Draw", symbol: "equal")
            }
        }
    }

    private func button(_ key: String, fallback: String, symbol: String) -> some View {
        let picked = result == key
        return Button {
            pick(key)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.title2)
                Text(labels[key] ?? fallback).font(.headline)
            }
            .foregroundStyle(picked ? .black : .primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .glassEffect(picked ? .regular.tint(Color("Neon")).interactive() : .regular.interactive(), in: .rect(cornerRadius: 18))
        .accessibilityAddTraits(picked ? .isSelected : [])
    }
}

/// One player's place: their art and name, then the numbers 1…N to tap.
private struct PlaceRow: View {
    let name: String
    let art: String
    let place: Int?
    let of: Int
    let pick: (Int) -> Void

    var body: some View {
        HStack(spacing: 10) {
            CardArt(name: art)
                .frame(width: 32, height: 32)
                .clipShape(.circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).lineLimit(1)
                if place == 1 {
                    Label("Winner", systemImage: "trophy.fill")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                }
            }
            Spacer(minLength: 4)
            HStack(spacing: 4) {
                ForEach(1...of, id: \.self) { number in
                    Button("\(number)") { pick(number) }
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .frame(width: 34, height: 34)
                        .foregroundStyle(place == number ? .black : .primary)
                        .background(Circle().fill(place == number ? Color("Neon") : Color.secondary.opacity(0.15)))
                        .buttonStyle(.plain)
                        .accessibilityLabel("Place \(number)")
                        .accessibilityAddTraits(place == number ? .isSelected : [])
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(name)
    }
}

/// Quick picks as chips that wrap onto the next line.
private struct ChoiceChips: View {
    let title: String
    let choices: [Options.Choice]
    let picked: [String]
    let toggle: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            Wrap(spacing: 6) {
                ForEach(choices) { choice in
                    let on = picked.contains(choice.key)
                    Button(choice.label) { toggle(choice.key) }
                        .font(.subheadline)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .foregroundStyle(on ? .black : .primary)
                        .background(Capsule().fill(on ? Color("Neon") : Color.secondary.opacity(0.15)))
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// Lays its children out in rows, starting a new row when one is full.
private struct Wrap: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(for: subviews, width: proposal.width ?? .infinity)
        let height = rows.map { $0.height }.reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(for: subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.items {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private func rows(for subviews: Subviews, width: CGFloat) -> [(items: [Int], width: CGFloat, height: CGFloat)] {
        var rows: [(items: [Int], width: CGFloat, height: CGFloat)] = []
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if let last = rows.last, last.width + spacing + size.width <= width {
                rows[rows.count - 1].items.append(index)
                rows[rows.count - 1].width += spacing + size.width
                rows[rows.count - 1].height = max(last.height, size.height)
            } else {
                rows.append(([index], size.width, size.height))
            }
        }
        return rows
    }
}

/// Picks who sat at the table: a known opponent deck, or a commander typed in (it becomes a new
/// opponent deck, or joins the newest one with that commander, like on the server).
private struct OpponentPicker: View {
    let taken: Set<String>
    let add: (GameDraft.Seat) -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List {
                if !typed.isEmpty {
                    Section {
                        Button {
                            Task { await addTyped() }
                        } label: {
                            Label("New Opponent: \(typed)", systemImage: "plus.circle")
                        }
                    } footer: {
                        Text("Type the commander's English name, as on the card.")
                    }
                }
                Section {
                    ForEach(shown) { opponent in
                        Button {
                            add(.init(opponentID: opponent.id, commander: opponent.commanders.first ?? opponent.title,
                                      colors: opponent.colors ?? ""))
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                CardArt(name: opponent.commanders.first ?? "")
                                    .frame(width: 36, height: 36)
                                    .clipShape(.circle)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(opponent.title).lineLimit(1)
                                    if let player = opponent.player, !player.isEmpty {
                                        Text(player).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                } header: {
                    if !shown.isEmpty { Text("Your Opponents") }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Name, player or commander")
            .navigationTitle("Add Opponent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", role: .cancel) { dismiss() } }
            }
        }
    }

    private var typed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The known opponents not at the table yet, filtered by the search.
    private var shown: [Opponent] {
        (model.library?.opponents ?? []).filter { opponent in
            !taken.contains(opponent.id) && (typed.isEmpty
                || ([opponent.title, opponent.player ?? ""] + opponent.commanders).contains { $0.localizedStandardContains(typed) })
        }
    }

    /// A typed commander, spelt the way Scryfall knows it when it finds the card (so its art shows and the
    /// server can link it to the same commander next time).
    private func addTyped() async {
        let card = try? await model.cards.card(named: typed)
        add(.init(commander: card?.name ?? typed, colors: card?.colors ?? ""))
        dismiss()
    }
}
