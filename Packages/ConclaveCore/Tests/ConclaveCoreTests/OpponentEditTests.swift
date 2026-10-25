import Testing
@testable import ConclaveCore

@Suite struct OpponentEditTests {
    static let base = APICasesTests.file["bases"]!["default"]!
    static let library = try! ReadModel.decode(base)
    /// o1: no label, played by Tim, bracket 4, tag "combo".
    static let tim = library.opponents.first { $0.id == "o1" }!

    func opponent(_ id: String, after ops: [PendingOp]) throws -> Opponent {
        try #require(try ReadModel.decode(Optimistic.apply(ops, to: Self.base)).opponents.first { $0.id == id })
    }

    @Test func nothingChangedSendsNothing() {
        #expect(OpponentEdit.update(Self.tim, to: OpponentEdit.Fields(of: Self.tim)) == nil)
        // spaces around a name are no change either
        #expect(OpponentEdit.update(Self.tim, to: .init(label: " ", player: "Tim ", bracket: 4)) == nil)
    }

    @Test func onlyTheChangedFieldsGoWithTheirOldValues() throws {
        let payload = try #require(OpponentEdit.update(Self.tim, to: .init(label: "Tim's Combo", player: "Tim", bracket: nil)))
        #expect(payload == .object([
            "id": .string("o1"), "label": .string("Tim's Combo"), "bracket": .null,
            "prev": .object(["label": .string(""), "bracket": .int(4)]),
        ]))
        let edited = try opponent("o1", after: [PendingOp(type: "opponent.update", payload: payload)])
        #expect(edited.title == "Tim's Combo (Atraxa, Praetors' Voice)")
        #expect(edited.bracket == nil)
    }

    @Test func undoPutsTheOldValuesBack() throws {
        let payload = try #require(OpponentEdit.update(Self.tim, to: .init(label: "", player: "Anna", bracket: 2)))
        let op = PendingOp(type: "opponent.update", payload: payload)
        let inverse = try #require(Outbox.inverse(op.type, op.payload))
        let back = try opponent("o1", after: [op, PendingOp(type: inverse.type, payload: inverse.payload)])
        #expect(back.player == "Tim")
        #expect(back.bracket == 4)
    }

    @Test func aTagChipTurnsOnAndOff() throws {
        let off = OpponentEdit.toggle("combo", on: Self.tim)
        #expect(off["tags"] == .array([]))
        #expect(off["prev"]?["tags"] == .array([.string("combo")]))
        let on = OpponentEdit.toggle("stax", on: Self.tim)
        #expect(try opponent("o1", after: [PendingOp(type: "opponent.update", payload: on)]).tags == ["combo", "stax"])
    }

    @Test func aNoteNeedsText() throws {
        #expect(OpponentEdit.note("  \n", on: Self.tim) == nil)
        let payload = try #require(OpponentEdit.note(" Ramps hard \n", on: Self.tim))
        #expect(payload["text"] == .string("Ramps hard"))
        #expect(payload["note_id"]?.string?.count == 8)
        #expect(try opponent("o1", after: [PendingOp(type: "opponent.note", payload: payload)]).notes.first?.text == "Ramps hard")
    }
}
