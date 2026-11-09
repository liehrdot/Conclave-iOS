import Foundation

/// The operations the app sends to `POST /api/app/ops`, by their wire names (`TYPES` in Conclave's
/// `appops.py`). One list, so a misspelt type can't compile, and a switch over it can't miss one.
public enum OpType: String, Codable, CaseIterable, Sendable {
    case gameAdd = "game.add"
    case gameDelete = "game.delete"
    case opponentAdd = "opponent.add"
    case opponentUpdate = "opponent.update"
    case opponentNote = "opponent.note"
    case opponentNoteDelete = "opponent.note_delete"
    case opponentDelete = "opponent.delete"
    case deckEdit = "deck.edit"
    case deckFlags = "deck.flags"
    case deckPinOrder = "deck.pin_order"
    case collectionAdd = "collection.add"
    case collectionUpdate = "collection.update"
}

/// One change as the edit builders shape it (`DeckEdit`, `CollectionEdit`, `OpponentEdit`, `GameDraft`,
/// `CollectionAddDraft`): the type and its payload together, so a screen can't pair a payload with
/// the wrong type. `Outbox.add` turns it into a `PendingOp`.
public struct Change: Equatable, Sendable {
    public var type: OpType
    public var payload: JSONValue

    public init(_ type: OpType, _ payload: JSONValue) {
        self.type = type
        self.payload = payload
    }
}
