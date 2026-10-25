import Foundation
import Testing
@testable import ConclaveCore

@Suite struct GameDraftTests {
    /// Conclave's case base: Meren's last game, 2026-10-02 20:00, against Atraxa (o1).
    static let base = APICasesTests.file["bases"]!["default"]!
    static let library = try! ReadModel.decode(base)
    static let lastGame = ReadModel.date("2026-10-02T20:00:00+00:00")!

    func draft(hoursLater: Double = 1) -> GameDraft {
        GameDraft(deck: "meren", library: Self.library, now: Self.lastGame.addingTimeInterval(hoursLater * 3600))
    }

    @Test func theSameTableWithinEightHours() {
        let soon = draft(hoursLater: 2)
        #expect(soon.rematch)
        #expect(soon.seats.map(\.opponentID) == ["o1"])
        #expect(soon.seats.map(\.commander) == ["Atraxa, Praetors' Voice"])
        #expect(soon.seats.first?.colors == "WUBG")
        let later = draft(hoursLater: 9)
        #expect(!later.rematch && later.seats.isEmpty)
    }

    @Test func aWinIsFirstPlaceALossIsNot() {
        var game = draft()
        game.setResult("win")
        #expect(game.place == 1)
        game.setResult("loss")
        #expect(game.place == nil)
        var alone = draft(hoursLater: 9)
        alone.setResult("win")
        #expect(alone.place == nil)  // no opponents: no places
        #expect(alone.canSave)
    }

    @Test func placesFillTheLastOneAndDecideTheResult() {
        var game = draft(hoursLater: 9)
        game.add(.init(opponentID: "o1", commander: "Atraxa, Praetors' Voice"))
        game.add(.init(commander: "Edgar Markov"))
        #expect(game.tableSize == 3)
        game.setPlace(1, seat: 0)
        game.setPlace(3, seat: 1)
        #expect(game.place == 2)  // the place that was left
        #expect(game.result == "loss")
        game.setPlace(1)
        #expect(game.result == "win")
        game.setPlace(1)  // the same again clears it
        #expect(game.place == nil)
        #expect(game.result == "win")  // a cleared place doesn't change the result
        game.setResult("draw")
        game.setPlace(2)
        #expect(game.result == "draw")  // a draw stays a draw
    }

    @Test func aSmallerTableDropsPlacesThatNoLongerFit() {
        var game = draft(hoursLater: 9)
        game.add(.init(commander: "Edgar Markov"))
        game.add(.init(commander: "Krenko, Mob Boss"))
        game.setPlace(3)
        game.setPlace(2, seat: 1)
        game.removeSeat(at: 0)
        #expect(game.tableSize == 2)
        #expect(game.place == nil)
        #expect(game.seats.first?.place == 2)
        #expect(!game.rematch)
    }

    @Test func noTwinsAndAtMostFiveOpponents() {
        var game = draft()
        game.add(.init(opponentID: "o1", commander: "Atraxa, Praetors' Voice"))
        #expect(game.seats.count == 1)
        for name in ["A", "B", "C", "D", "E", "F"] { game.add(.init(commander: name)) }
        #expect(game.seats.count == GameDraft.maxOpponents)
    }

    @Test func savesAsTheServerReadsIt() throws {
        var game = draft()
        game.add(.init(commander: "Edgar Markov"))
        #expect(game.payload == nil)
        game.setPlace(1, seat: 1)
        game.setPlace(2)
        game.turn = 9
        game.issues = ["mana"]
        game.note = "  Close one  "
        let payload = try #require(game.payload)
        #expect(payload["game"]?["result"] == .string("loss"))
        #expect(payload["game"]?["place"] == .int(2))
        #expect(payload["game"]?["note"] == .string("Close one"))
        #expect(payload["opponents"]?[0]?["id"] == .string("o1"))
        #expect(payload["opponents"]?[0]?["new_id"] == .null)
        #expect(payload["opponents"]?[1]?["new_id"]?.string?.count == 8)
        #expect(payload == game.payload)  // the same every time: a resent op makes the same opponent

        // and the phone shows it at once, linked the way the server will
        let shown = try ReadModel.decode(Optimistic.apply([PendingOp(type: "game.add", payload: payload)], to: Self.base))
        let logged = try #require(shown.games.first { $0.id == game.id })
        #expect(logged.opponents == ["Atraxa, Praetors' Voice", "Edgar Markov"])
        #expect(logged.place == 2 && logged.turn == 9)
        #expect(shown.opponents.contains { $0.commanders == ["Edgar Markov"] })
    }
}
