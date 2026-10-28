import Foundation

/// "Add to Deck": one card into a deck or onto its maybe list, as one `deck.edit` (`appops._deck_edit`), like the
/// iPad builder's `+` and `?` in the PWA's `build.js`. The payload carries `prev`, the `deck.edit` that takes it
/// back, for "Undo" (the server reads only the keys it knows).
public enum DeckEdit {
    public enum Spot: String, Sendable, CaseIterable {
        case deck, maybe
    }

    /// Where a card is in a deck now.
    public enum Place: Equatable, Sendable {
        case commander
        case deck(qty: Int)
        case maybe
        case none
    }

    public static func place(of name: String, in deck: Deck) -> Place {
        if deck.commanders.contains(name) { return .commander }
        if let card = deck.cards.first(where: { $0.name == name }) { return .deck(qty: card.qty ?? 1) }
        if deck.maybe.contains(where: { $0.name == name }) { return .maybe }
        return .none
    }

    /// The `deck.edit` payload that puts `name` into the deck or onto its maybe list; nil when there's nothing to
    /// do: a commander, a card that is already there (a basic land can go in again: one more copy).
    public static func add(_ name: String, card: Card?, to deck: Deck, as spot: Spot) -> JSONValue? {
        let slug = JSONValue.string(deck.slug)
        let place = place(of: name, in: deck)
        let category = deck.cards.first { $0.name == name }?.category ?? deck.maybe.first { $0.name == name }?.category
        switch (spot, place) {
        case (_, .commander), (.maybe, .maybe):
            return nil
        case (.deck, .deck(let qty)):
            guard basics.contains(name) else { return nil }  // singleton
            return .object(["deck": slug, "add": .array([.object(["name": .string(name), "qty": .int(1)])]),
                            "prev": .object(["set_qty": .object([name: .int(qty)])])])
        case (.deck, .maybe):  // off the maybe list into the deck, keeping its category
            let back: [String: JSONValue] = ["name": .string(name), "category": .string(category ?? "Synergy")]
            return .object(["deck": slug, "add": .array([.object(["name": .string(name), "qty": .int(1),
                                                                  "category": .string(category ?? guessCategory(name, card: card))])]),
                            "prev": .object(["maybe_add": .array([.object(back)])])])
        case (.deck, .none):
            return .object(["deck": slug, "add": .array([.object(["name": .string(name), "qty": .int(1),
                                                                  "category": .string(guessCategory(name, card: card))])]),
                            "prev": .object(["remove": .array([.string(name)])])])
        case (.maybe, .deck(let qty)):  // out of the deck onto the list; "Undo" puts it back
            let back: [String: JSONValue] = ["name": .string(name), "qty": .int(qty), "category": .string(category ?? "Synergy")]
            return .object(["deck": slug, "maybe_add": .array([.object(["name": .string(name)])]),
                            "prev": .object(["add": .array([.object(back)])])])
        case (.maybe, .none):
            return .object(["deck": slug, "maybe_add": .array([.object(["name": .string(name),
                                                                        "category": .string(guessCategory(name, card: card))])]),
                            "prev": .object(["maybe_remove": .array([.string(name)])])])
        }
    }

    static let basics: Set = ["Plains", "Island", "Swamp", "Mountain", "Forest", "Wastes",
                              "Snow-Covered Plains", "Snow-Covered Island", "Snow-Covered Swamp",
                              "Snow-Covered Mountain", "Snow-Covered Forest"]

    /// A first category from the card's type line and rules text. Mirrors `guessCategory()` in the PWA's
    /// `build.js` (and so `deckedit.guess_category`); the PC sorts it out when it checks the deck.
    public static func guessCategory(_ name: String, card: Card?) -> String {
        if basics.contains(name) { return "Land" }
        let type = card?.faces.first?.typeLine ?? ""
        let text = (card?.faces.map(\.text).joined(separator: "\n") ?? "").lowercased()
        func has(_ pattern: String, _ in: String) -> Bool { `in`.range(of: pattern, options: .regularExpression) != nil }
        if has(#"\bLand\b"#, type) { return "Land" }
        if has(#"(destroy|exile) all |all creatures get -|each creature gets -|return all (nonland|creatures)"#, text) { return "Board Wipe" }
        if has(#"counter target|(destroy|exile) target|return target (creature|nonland|permanent)[^.]* to its owner's hand"#, text) { return "Removal" }
        if has(#"add \{|add (one|two|three) mana|search your library for (a|up to \w+) (basic )?lands?"#, text) { return "Ramp" }
        if has(#"draws? (a|an additional|two|three|four|x|that many) cards?"#, text) { return "Draw" }
        if has(#"(hexproof|indestructible|protection from|phase out)"#, text) && has(#"(you control|target creature)"#, text) { return "Protection" }
        return "Synergy"
    }
}
