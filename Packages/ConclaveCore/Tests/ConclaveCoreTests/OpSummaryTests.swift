import Testing
@testable import ConclaveCore

@Suite struct OpSummaryTests {
    static let library = try! ReadModel.decode(APICasesTests.file["bases"]!["default"]!)

    func summary(_ type: String, _ payload: [String: JSONValue]) -> String {
        PendingOp(type: type, payload: .object(payload)).summary(in: Self.library)
    }

    @Test func gamesNameTheResultAndTheDeck() {
        let game: JSONValue = .object(["id": .string("g9"), "deck": .string("meren"), "result": .string("loss")])
        #expect(summary("game.add", ["game": game]) == "Loss with Meren")
        #expect(summary("game.delete", ["deck": .string("meren"), "id": .string("g1")]) == "Removed game with Meren")
        // a deck the phone doesn't know (deleted on the PC meanwhile) keeps its slug
        #expect(summary("game.delete", ["deck": .string("gone"), "id": .string("g1")]) == "Removed game with gone")
    }

    @Test func opponentsNameTheOpponent() {
        #expect(summary("opponent.note", ["id": .string("o2"), "note_id": .string("n"), "text": .string("x")]) == "Note on Goblins (Krenko, Mob Boss)")
        #expect(summary("opponent.update", ["id": .string("o9")]) == "Changes to an opponent")
        #expect(summary("opponent.add", ["opponent": .object(["id": .string("o9"), "commanders": .array([.string("Edgar Markov")])])])
            == "New opponent Edgar Markov")
        #expect(summary("deck.flags", [:]) == "A change")
    }
}
