import ConclaveCore
import SwiftUI

/// "Edit Opponent": the deck's own name, who plays it and its rough bracket. Games, the record and the
/// notes stay linked by the opponent's id, so nothing is lost. Mirrors the PWA's `editOpponentSheet()`;
/// changing the commander follows later (it needs a card search).
struct EditOpponentView: View {
    let opponent: Opponent
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var fields: OpponentEdit.Fields

    init(opponent: Opponent) {
        self.opponent = opponent
        _fields = State(initialValue: OpponentEdit.Fields(of: opponent))
    }

    /// The players from earlier games, except the one already typed in.
    private var players: [Options.Choice] {
        (model.library?.players ?? []).filter { $0 != fields.player }.map { Options.Choice(key: $0, label: $0) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(opponent.commanders.joined(separator: " + "), text: $fields.label)
                        .textInputAutocapitalization(.words)
                } header: {
                    Text("Name")
                } footer: {
                    Text("Optional. Without one, it goes by its commander.")
                }
                Section {
                    TextField("Who plays it", text: $fields.player)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                    if !players.isEmpty {
                        ChoiceChips(title: "From earlier games", choices: players, picked: []) { fields.player = $0 }
                    }
                } header: {
                    Text("Player")
                }
                Section {
                    Picker("Bracket", selection: $fields.bracket) {
                        Text("?").tag(Int?.none).accessibilityLabel("Not sure")
                        ForEach(OpponentEdit.brackets, id: \.self) { Text("\($0)").tag(Int?.some($0)) }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Roughly Bracket")
                } footer: {
                    Text("Games, the record and notes stay with this deck.")
                }
            }
            .navigationTitle("Edit Opponent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", role: .confirm) {
                        if let payload = OpponentEdit.update(opponent, to: fields) {
                            Task { await model.save("opponent.update", payload) }
                        }
                        dismiss()
                    }
                }
            }
        }
    }
}

/// "Add Note": a few words about the deck for next time ("Wipes the board on turn 6").
struct AddNoteView: View {
    let opponent: Opponent
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What did you notice?", text: $text, axis: .vertical)
                        .lineLimit(4...10)
                        .focused($focused)
                } footer: {
                    Text("Notes show on this opponent's screen, here and on your PC.")
                }
            }
            .navigationTitle("Note on \(opponent.title)")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { focused = true }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", role: .confirm) {
                        if let payload = OpponentEdit.note(text, on: opponent) {
                            Task { await model.save("opponent.note", payload) }
                        }
                        dismiss()
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
