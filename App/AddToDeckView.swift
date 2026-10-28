import ConclaveCore
import SwiftUI

/// "Add to a Deck" from a card's sheet: into the deck or onto its maybe list (remembered), then a tap on a
/// deck saves one `deck.edit` (`DeckEdit.add`) and closes; the toast has "Undo". A deck where the card
/// can't go (it's the commander, or already there) says so instead.
struct AddToDeckView: View {
    let name: String
    let card: Card?
    /// After saving: the card sheet below closes too, so the toast with "Undo" shows.
    var saved: () -> Void = {}
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @AppStorage("addToSpot") private var spot: DeckEdit.Spot = .deck

    var body: some View {
        NavigationStack {
            List {
                Section {
                    SpotPicker(spot: $spot)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
                Section {
                    ForEach(model.library?.decks ?? []) { deck in
                        let payload = DeckEdit.add(name, card: card, to: deck, as: spot)
                        Button {
                            guard let payload else { return }
                            Task {
                                _ = await model.save("deck.edit", payload)
                                dismiss()
                                saved()
                            }
                        } label: {
                            HStack(spacing: 12) {
                                CardArt(name: deck.commanders.first ?? "")
                                    .frame(width: 52, height: 38)
                                    .clipShape(.rect(cornerRadius: 6))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(deck.name).foregroundStyle(.primary)
                                    if let note = DeckPlaceText.text(DeckEdit.place(of: name, in: deck)) {
                                        Text(note).font(.subheadline).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .frame(minHeight: 44)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .disabled(payload == nil)
                        .materialRow()
                    }
                } header: {
                    SectionTitle("Decks")
                }
            }
            .artList(over: name)
            .overlay {
                if model.library?.decks.isEmpty ?? true {
                    ContentUnavailableView("No Decks Yet", systemImage: "rectangle.stack",
                                           description: Text("Decks you build on your PC show up here."))
                }
            }
            .navigationTitle("Add \(name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .task { await model.cards.prefetch((model.library?.decks ?? []).flatMap(\.commanders)) }
    }
}

/// "Add Cards" on a deck's screen: find a card by name (English or German), and a tap puts it into the deck
/// or onto its maybe list, picked above. The sheet stays open for the next card; each row says where its
/// card is now, as the change shows at once.
struct DeckCardSearch: View {
    let slug: String
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @AppStorage("addToSpot") private var spot: DeckEdit.Spot = .deck
    @State private var query = ""
    @State private var hits: [NameHit] = []
    @State private var problem: String?
    @State private var searched = ""

    private var deck: Deck? { model.library?.decks.first { $0.slug == slug } }
    private var typed: String { query.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    SpotPicker(spot: $spot)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
                if let deck {
                    ForEach(hits) { hit in row(hit, in: deck) }
                }
            }
            .artList(over: deck?.commanders.first ?? "")
            .overlay { placeholder }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Card name, English or German")
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .task(id: typed) { await search() }
            .navigationTitle(deck.map { "Add to \($0.name)" } ?? "Add Cards")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func row(_ hit: NameHit, in deck: Deck) -> some View {
        let place = DeckEdit.place(of: hit.name, in: deck)
        let payload = DeckEdit.add(hit.name, card: hit.card, to: deck, as: spot)
        return Button {
            guard let payload else { return }
            Task { _ = await model.save("deck.edit", payload) }
        } label: {
            HStack(spacing: 12) {
                CardArt(name: hit.name)
                    .frame(width: 52, height: 38)
                    .clipShape(.rect(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 2) {
                    Text(hit.german ?? hit.name).foregroundStyle(.primary)
                    if hit.german != nil { Text(hit.name).font(.subheadline).foregroundStyle(.secondary) }
                    if let note = DeckPlaceText.text(place) {
                        Text(note).font(.caption).foregroundStyle(.secondary)
                    } else if !hit.type.isEmpty {
                        Text(hit.type).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: payload == nil ? "checkmark.circle.fill" : spot == .deck ? "plus.circle" : "questionmark.circle")
                    .font(.title2)
                    .foregroundStyle(payload == nil ? Color.secondary : Color.accentColor)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(payload == nil)
        .accessibilityHint(payload == nil ? "" : spot == .deck ? "Adds it to the deck" : "Puts it on the maybe list")
        .materialRow()
    }

    @ViewBuilder private var placeholder: some View {
        if deck == nil {
            ContentUnavailableView("Deck Removed", systemImage: "rectangle.stack", description: Text("It was deleted on your PC."))
        } else if let problem, !typed.isEmpty {
            ContentUnavailableView("Can't Search", systemImage: "wifi.exclamationmark", description: Text(problem))
        } else if typed.isEmpty {
            ContentUnavailableView("Add Cards", systemImage: "magnifyingglass",
                                   description: Text("Type a card's name, in English or German. A tap adds it."))
        } else if searched == typed, hits.isEmpty {
            ContentUnavailableView.search(text: typed)
        }
    }

    /// Searches once typing paused (the task restarts on every key, so only the last one runs).
    private func search() async {
        let wanted = typed
        guard !wanted.isEmpty else {
            hits = []
            problem = nil
            return
        }
        do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
        do {
            let found = try await model.cards.scryfall.find(name: wanted)
            guard wanted == typed else { return }
            await model.cards.remember(found.compactMap(\.card))
            hits = found
            problem = nil
        } catch is CancellationError {
            return
        } catch {
            guard wanted == typed else { return }
            if case .offline? = error as? CardError {
                problem = "No connection to Scryfall."
            } else {
                problem = "Scryfall didn't answer. Try again in a moment."
            }
        }
        searched = wanted
    }
}

/// Deck or maybe list, as a segmented control.
struct SpotPicker: View {
    @Binding var spot: DeckEdit.Spot

    var body: some View {
        Picker("Add to", selection: $spot) {
            Text("Deck").tag(DeckEdit.Spot.deck)
            Text("Maybe List").tag(DeckEdit.Spot.maybe)
        }
        .pickerStyle(.segmented)
    }
}

/// Where a card is in a deck, in words; nil when it isn't there.
enum DeckPlaceText {
    static func text(_ place: DeckEdit.Place) -> String? {
        switch place {
        case .commander: "The commander"
        case .deck(let qty): qty > 1 ? "\(qty) in the deck" : "In the deck"
        case .maybe: "On the maybe list"
        case .none: nil
        }
    }
}
