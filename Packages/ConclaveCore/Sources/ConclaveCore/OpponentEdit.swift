import Foundation

/// Changes to one opponent deck from its screen, as the payloads of `opponent.update` and `opponent.note`.
/// Each update carries `prev`, the old values, so "Undo" can send them back (`Outbox.inverse`).
/// Mirrors the PWA: `editOpponentSheet()` → `commit()` in `forms.js`, the tag chips and the note form in
/// `screens.js` `opponent()`.
public enum OpponentEdit {
    /// What the edit sheet changes. The commanders stay: changing them needs a card search (a later step).
    public struct Fields: Equatable, Sendable {
        public var label: String
        public var player: String
        public var bracket: Int?

        public init(label: String = "", player: String = "", bracket: Int? = nil) {
            self.label = label
            self.player = player
            self.bracket = bracket
        }

        public init(of opponent: Opponent) {
            self.init(label: opponent.label ?? "", player: opponent.player ?? "", bracket: opponent.bracket)
        }
    }

    /// The brackets an opponent can be guessed at (nil = not sure).
    public static let brackets = 1...5

    /// Only the fields that changed, with their old values in `prev`; nil when nothing changed.
    public static func update(_ opponent: Opponent, to fields: Fields) -> JSONValue? {
        let before = Fields(of: opponent)
        let now = Fields(label: trimmed(fields.label), player: trimmed(fields.player), bracket: fields.bracket)
        var payload: [String: JSONValue] = ["id": .string(opponent.id)]
        var prev: [String: JSONValue] = [:]
        if now.label != before.label {
            payload["label"] = .string(now.label)
            prev["label"] = .string(before.label)
        }
        if now.player != before.player {
            payload["player"] = .string(now.player)
            prev["player"] = .string(before.player)
        }
        if now.bracket != before.bracket {
            payload["bracket"] = now.bracket.map(JSONValue.int) ?? .null
            prev["bracket"] = before.bracket.map(JSONValue.int) ?? .null
        }
        guard !prev.isEmpty else { return nil }
        payload["prev"] = .object(prev)
        return .object(payload)
    }

    /// The opponent's tags after one chip was tapped: on when it was off, off when it was on.
    public static func toggle(_ tag: String, on opponent: Opponent) -> JSONValue {
        let now = opponent.tags.contains(tag) ? opponent.tags.filter { $0 != tag } : opponent.tags + [tag]
        return .object([
            "id": .string(opponent.id),
            "tags": .array(now.map(JSONValue.string)),
            "prev": .object(["tags": .array(opponent.tags.map(JSONValue.string))]),
        ])
    }

    /// A new note; nil when there's nothing in it. The server keeps the first 1,000 characters.
    public static func note(_ text: String, on opponent: Opponent) -> JSONValue? {
        let body = trimmed(text)
        guard !body.isEmpty else { return nil }
        return .object([
            "id": .string(opponent.id),
            "note_id": .string(String(PendingOp.newID().prefix(8))),
            "text": .string(body),
        ])
    }

    private static func trimmed(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
}
