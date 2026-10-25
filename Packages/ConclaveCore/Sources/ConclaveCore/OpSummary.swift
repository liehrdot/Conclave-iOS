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
        default:
            return "A change"
        }
    }
}
