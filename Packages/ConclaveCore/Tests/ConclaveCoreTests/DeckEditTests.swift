import Foundation
import Testing
@testable import ConclaveCore

@Suite struct DeckEditTests {
    static func card(_ name: String, type: String, text: String) -> Card {
        Card(name: name, faces: [.init(name: name, manaCost: "", typeLine: type, text: text, stats: nil, image: nil)],
             colors: "", image: nil, art: nil, link: nil, lang: "en")
    }

    /// The shared cases' Meren: Forest ×30, Sakura-Tribe Elder, Sol Ring; Grim Backwoods on the maybe list.
    static func meren() throws -> (base: JSONValue, deck: Deck) {
        let base = try #require(APICasesTests.file["bases"]?["default"])
        let deck = try #require(try ReadModel.decode(base).decks.first { $0.slug == "meren" })
        return (base, deck)
    }

    static func after(_ payload: JSONValue, on base: JSONValue) throws -> Deck {
        let op = PendingOp(type: "deck.edit", payload: payload)
        return try #require(try ReadModel.decode(Optimistic.apply([op], to: base)).decks.first { $0.slug == "meren" })
    }

    /// Applies the edit, then its "Undo": the deck must look as it did.
    static func roundTrip(_ name: String, card: Card? = nil, as spot: DeckEdit.Spot) throws -> Deck {
        let (base, deck) = try meren()
        let payload = try #require(DeckEdit.add(name, card: card, to: deck, as: spot))
        let edit = PendingOp(type: "deck.edit", payload: payload)
        let back = try #require(Outbox.inverse(edit.type, edit.payload))
        let undone = try #require(try ReadModel.decode(Optimistic.apply([edit, PendingOp(type: back.type, payload: back.payload)], to: base))
            .decks.first { $0.slug == "meren" })
        #expect(undone.cards == deck.cards && undone.maybe == deck.maybe, "\(name) → \(spot): Undo")
        return try after(payload, on: base)
    }

    @Test func aNewCardGoesIntoTheDeckWithAGuessedCategory() throws {
        let arena = Self.card("Phyrexian Arena", type: "Enchantment", text: "At the beginning of your upkeep, you draw a card and you lose 1 life.")
        let deck = try Self.roundTrip("Phyrexian Arena", card: arena, as: .deck)
        #expect(deck.cards.contains(Deck.Card(name: "Phyrexian Arena", qty: 1, category: "Draw")))
        #expect(deck.checking && deck.version == 3)
    }

    @Test func aNewCardGoesOntoTheMaybeList() throws {
        let deck = try Self.roundTrip("Viscera Seer", as: .maybe)
        #expect(deck.maybe.map(\.name) == ["Grim Backwoods", "Viscera Seer"])
        #expect(!deck.cards.contains { $0.name == "Viscera Seer" })
    }

    @Test func aMaybeCardMovesIntoTheDeckAndBack() throws {
        let deck = try Self.roundTrip("Grim Backwoods", as: .deck)
        #expect(deck.cards.contains(Deck.Card(name: "Grim Backwoods", qty: 1, category: "Draw")))  // keeps its category
        #expect(deck.maybe.isEmpty)
    }

    @Test func aDeckCardMovesOntoTheMaybeListAndBack() throws {
        let deck = try Self.roundTrip("Sol Ring", as: .maybe)
        #expect(deck.maybe.contains(Deck.Card(name: "Sol Ring", qty: nil, category: "Ramp")))
        #expect(!deck.cards.contains { $0.name == "Sol Ring" })
    }

    @Test func aBasicLandGetsOneMoreCopy() throws {
        let deck = try Self.roundTrip("Forest", as: .deck)
        #expect(deck.cards.first { $0.name == "Forest" }?.qty == 31)
    }

    @Test func nothingToDo() throws {
        let (_, deck) = try Self.meren()
        #expect(DeckEdit.add("Meren of Clan Nel Toth", card: nil, to: deck, as: .deck) == nil)  // the commander
        #expect(DeckEdit.add("Meren of Clan Nel Toth", card: nil, to: deck, as: .maybe) == nil)
        #expect(DeckEdit.add("Sol Ring", card: nil, to: deck, as: .deck) == nil)  // singleton
        #expect(DeckEdit.add("Grim Backwoods", card: nil, to: deck, as: .maybe) == nil)  // already there
        #expect(DeckEdit.place(of: "Forest", in: deck) == .deck(qty: 30))
        #expect(DeckEdit.place(of: "Grim Backwoods", in: deck) == .maybe)
        #expect(DeckEdit.place(of: "Ponder", in: deck) == .none)
    }

    @Test func categoriesAreGuessedLikeTheWebApp() {
        func guess(_ type: String, _ text: String) -> String { DeckEdit.guessCategory("X", card: Self.card("X", type: type, text: text)) }
        #expect(DeckEdit.guessCategory("Swamp", card: nil) == "Land")
        #expect(guess("Land", "{T}: Add {C}.") == "Land")
        #expect(guess("Sorcery", "Destroy all creatures. They can't be regenerated.") == "Board Wipe")
        #expect(guess("Instant", "Exile target creature.") == "Removal")
        #expect(guess("Artifact", "{T}: Add {C}{C}.") == "Ramp")
        #expect(guess("Sorcery", "Draw two cards.") == "Draw")
        #expect(guess("Instant", "Target creature you control gains hexproof until end of turn.") == "Protection")
        #expect(guess("Creature — Elf", "Flying") == "Synergy")
        #expect(DeckEdit.guessCategory("X", card: nil) == "Synergy")
    }

    @Test func theToastSaysWhatHappened() throws {
        let (base, deck) = try Self.meren()
        let library = try ReadModel.decode(base)
        let into = PendingOp(type: "deck.edit", payload: try #require(DeckEdit.add("Ponder", card: nil, to: deck, as: .deck)))
        let maybe = PendingOp(type: "deck.edit", payload: try #require(DeckEdit.add("Ponder", card: nil, to: deck, as: .maybe)))
        #expect(into.summary(in: library) == "Ponder in \(deck.name)")
        #expect(maybe.summary(in: library) == "Ponder on \(deck.name)'s maybe list")
    }
}
