import Foundation
import Testing
@testable import ConclaveCore

/// Runs Conclave's shared operation cases (`ops.json`) through `Optimistic`: what the phone shows at
/// once must be what the server's model will hold after it applied the operation.
@Suite struct OptimisticTests {
    /// The types `Optimistic` handles so far; the others come with their screens.
    static let handled: Set = ["game.add", "game.delete", "opponent.add", "opponent.update", "opponent.note",
                               "opponent.note_delete", "opponent.delete"]

    static var cases: [JSONValue] {
        APICasesTests.cases.filter { handled.contains($0["op"]?["type"]?.string ?? "") }
    }

    static func run(_ item: JSONValue) throws -> (got: JSONValue, base: JSONValue) {
        let base = try #require(APICasesTests.file["bases"]?[item["base"]?.string ?? ""])
        let op = try JSONDecoder().decode(PendingOp.self, from: JSONEncoder().encode(
            JSONValue.object((item["op"]?.object ?? [:]).merging(["status": .string("pending")]) { $1 })))
        return (Optimistic.apply([op], to: base), base)
    }

    /// The server makes up ids for notes written with a game; the phone can't know them.
    static func withoutMadeUpNoteIDs(_ value: JSONValue?) -> JSONValue? {
        guard case .array(let opponents)? = value else { return value }
        return .array(opponents.map { o in
            guard var o = o.object else { return o }
            o["notes"] = .array((o["notes"]?.array ?? []).map { n in
                guard var n = n.object, n["game_id"] != .null else { return n }
                n["id"] = .null
                return .object(n)
            })
            return .object(o)
        })
    }

    @Test(arguments: cases.map { $0["name"]?.string ?? "?" })
    func matchesTheServer(_ name: String) throws {
        let item = try #require(Self.cases.first { $0["name"]?.string == name })
        let (got, base) = try Self.run(item)
        guard let after = item["after"]?.object else {
            #expect(got == base, "\(name): an op the server refuses must change nothing")
            return
        }
        for (key, want) in after {
            var mine = got[key], theirs: JSONValue? = want
            if key == "opponents" { mine = Self.withoutMadeUpNoteIDs(mine); theirs = Self.withoutMadeUpNoteIDs(theirs) }
            #expect(mine == theirs, "\(name): \(key) differs")
        }
        for (key, value) in base.object ?? [:] where after[key] == nil {
            #expect(got[key] == value, "\(name): \(key) changed but the server left it")
        }
    }

    @Test func opsBuildOnEachOtherAndFailedOnesAreLeftOut() throws {
        let base = try #require(APICasesTests.file["bases"]?["default"])
        let opponent = PendingOp(type: "opponent.add", payload: .object([
            "opponent": .object(["id": .string("o9"), "commanders": .array([.string("Edgar Markov")])])]))
        let game = PendingOp(type: "game.add", payload: .object([
            "game": .object(["id": .string("g9"), "deck": .string("meren"), "result": .string("loss"), "place": .int(2)]),
            "opponents": .array([.object(["id": .string("o9"), "place": .int(1)])])]))
        var refused = PendingOp(type: "game.delete", payload: .object(["deck": .string("meren"), "id": .string("g1")]))
        refused.status = .failed
        let got = Optimistic.apply([opponent, game, refused], to: base)

        let newest = try #require(got["games"]?[0])
        #expect(newest["id"] == .string("g9"))
        #expect(newest["opponents"] == .array([.string("Edgar Markov")]))
        #expect(newest["opponent_ids"] == .array([.string("o9")]))
        #expect(newest["opponent_places"] == .array([.int(1)]))
        #expect(got["games"]?.array?.contains { $0["id"] == .string("g1") } == true)  // the failed delete isn't shown
        let edgar = try #require(got["opponents"]?.array?.first { $0["id"] == .string("o9") })
        #expect(edgar["record"]?["games"] == .int(1) && edgar["record"]?["losses"] == .int(1))  // the user's record against it
        let meren = try #require(got["decks"]?.array?.first { $0["slug"] == .string("meren") })
        #expect(meren["record"]?["losses"] == .int(1))
    }

    @Test func noOpsLeaveTheModelAsItIs() throws {
        let base = try #require(APICasesTests.file["bases"]?["default"])
        #expect(Optimistic.apply([], to: base) == base)
    }
}
