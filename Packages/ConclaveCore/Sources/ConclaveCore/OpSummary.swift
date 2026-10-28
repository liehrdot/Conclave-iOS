import Foundation

extension PendingOp {
    /// What this change is, in a few words, for the undo toast and the list of waiting or refused
    /// changes ("Loss with Meren", "Note on Atraxa"). Like the PWA's toast texts (`RESULT_TEXT` in `forms.js`),
    /// in English.
    public func summary(in library: ReadModel?) -> String {
        let deck = { (slug: String?) in library?.decks.first { $0.slug == slug }?.name ?? slug ?? "a deck" }
        let opponent = { (id: String?) in library?.opponents.first { $0.id == id }?.title ?? "an opponent" }
        switch type {
        case "game.add":
            let game = payload["game"]
            let result = ["win": "Win", "loss": "Loss", "draw": "Draw"][game?["result"]?.string ?? ""] ?? "Game"
            return "\(result) with \(deck(game?["deck"]?.string))"
        case "game.delete":
            return "Removed game with \(deck(payload["deck"]?.string))"
        case "opponent.add":
            let commanders = (payload["opponent"]?["commanders"]?.array ?? []).compactMap(\.string)
            return "New opponent \(commanders.first ?? "")".trimmingCharacters(in: .whitespaces)
        case "opponent.update":
            return "Changes to \(opponent(payload["id"]?.string))"
        case "opponent.note":
            return "Note on \(opponent(payload["id"]?.string))"
        case "opponent.note_delete":
            return "Removed note on \(opponent(payload["id"]?.string))"
        case "opponent.delete":
            return "Removed \(opponent(payload["id"]?.string))"
        case "collection.add":
            let entry = payload["entry"]
            let name = entry?["name"]?.string ?? "a card"
            let qty = entry?["qty"]?.int ?? 1
            return qty < 0 ? "Removed \(name)" : qty == 1 ? name : "\(qty) × \(name)"
        case "collection.update":
            return collectionChange(in: library)
        case "deck.edit":
            let into = deck(payload["deck"]?.string)
            if let name = payload["add"]?[0]?["name"]?.string { return "\(name) in \(into)" }
            if let name = payload["maybe_add"]?[0]?["name"]?.string { return "\(name) on \(into)'s maybe list" }
            if let name = payload["remove"]?[0]?.string ?? payload["maybe_remove"]?[0]?.string { return "Removed \(name) from \(into)" }
            if let name = payload["set_qty"]?.object?.keys.first { return "\(name) in \(into)" }
            return "Changes to \(into)"
        default:
            return "A change"
        }
    }

    /// A `collection.update` in a few words: "Removed Sol Ring", "Sol Ring: 3 copies", "Sol Ring in Binder".
    private func collectionChange(in library: ReadModel?) -> String {
        let entry = library?.collection.first { $0.id == payload["id"]?.string }
        let name = entry?.name ?? payload["restore"]?["name"]?.string ?? "a card"
        if payload["restore"] != nil || payload["qty"]?.int == 0 { return "Removed \(name)" }
        if let qty = payload["qty"]?.int { return "\(name): \(qty) \(qty == 1 ? "copy" : "copies")" }
        if let proxy = payload["proxy"]?.bool { return "\(name) as \(proxy ? "a proxy" : "an original")" }
        if let foil = payload["foil"]?.bool { return foil ? "\(name) as foil" : "\(name) not foil" }
        if payload["place"] != nil || payload["place_deck"] != nil {
            if let slug = payload["place_deck"]?.string, !slug.isEmpty {
                return "\(name) in \(library?.decks.first { $0.slug == slug }?.name ?? slug)"
            }
            let place = payload["place"]?.string ?? ""
            return place.isEmpty ? "\(name) without a place" : "\(name) in \(place)"
        }
        return "Changes to \(name)"
    }
}
