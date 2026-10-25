import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import ConclaveCore

@Suite struct OutboxTests {
    let device = Device(server: URL(string: "https://sync.example.org")!, token: "tok", id: "dev1", name: "Flo's iPhone", serverID: "ab12")
    let game: JSONValue = .object(["game": .object(["id": .string("g1"), "deck": .string("meren"), "result": .string("win")])])

    func answer(_ results: String, seq: Int = 42) -> FakeTransport.Answer {
        .init(body: #"{"results": [\#(results)], "etag": "\"ab12-3f-\#(seq)\""}"#)
    }

    func tempFile() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("outbox-\(UUID().uuidString)/outbox.json")
    }

    @Test func newOpsLookLikeTheWebApps() {
        let op = PendingOp(type: "game.add", payload: game)
        #expect(op.id.count == 12 && op.id.allSatisfy(\.isHexDigit))
        #expect(op.status == .pending)
        #expect(PendingOp.now(Date(timeIntervalSince1970: 1_760_126_400)) == "2025-10-10T20:00:00+00:00")
    }

    @Test func opsSurviveARestart() async {
        let file = tempFile()
        let added = await Outbox(file: file).add("game.add", game)
        #expect(await Outbox(file: file).ops == [added])
    }

    @Test func flushSendsTheWireFormatAndMarksOpsSent() async throws {
        let outbox = Outbox(file: nil)
        let op = await outbox.add("game.add", game)
        let fake = FakeTransport(answer(#"{"id": "\#(op.id)", "ok": true}"#))
        let outcome = await outbox.flush(to: Server(device: device, transport: fake))
        #expect(outcome == .sent(etag: #""ab12-3f-42""#, more: false))
        let request = try #require(fake.requests.first)
        #expect(request.url?.absoluteString == "https://sync.example.org/api/app/ops")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer tok")
        let body = try JSONDecoder().decode([String: [[String: JSONValue]]].self, from: try #require(request.httpBody))
        #expect(body == ["ops": [["id": .string(op.id), "type": .string("game.add"), "payload": game, "at": .string(op.at)]]])
        let sent = try #require(await outbox.ops.first)
        #expect(sent.status == .sent && sent.ack == #""ab12-3f-42""#)
        #expect(await outbox.pending.isEmpty)
        #expect(await outbox.flush(to: Server(device: device, transport: fake)) == .nothing)
    }

    @Test func busyOpsStayAndRefusedOnesFail() async {
        let outbox = Outbox(file: nil)
        let busy = await outbox.add("game.add", game)
        let refused = await outbox.add("opponent.delete", .object(["id": .string("x")]))
        let fake = FakeTransport(answer(#"{"id": "\#(busy.id)", "ok": false, "retry": true}, {"id": "\#(refused.id)", "ok": false, "error": "Gegnerdeck nicht gefunden."}"#))
        _ = await outbox.flush(to: Server(device: device, transport: fake))
        #expect(await outbox.pending.map(\.id) == [busy.id])
        let failed = await outbox.failed
        #expect(failed.map(\.id) == [refused.id])
        #expect(failed.first?.error == "Gegnerdeck nicht gefunden.")
    }

    @Test func failuresBackOffAndForceSkipsTheWait() async {
        let outbox = Outbox(file: nil)
        await outbox.add("game.add", game)
        let fake = FakeTransport()
        fake.failure = URLError(.notConnectedToInternet)
        let server = Server(device: device, transport: fake)
        let start = Date(timeIntervalSince1970: 1000)
        #expect(await outbox.flush(to: server, now: start) == .failed(retryIn: .seconds(5)))
        #expect(await outbox.flush(to: server, now: start.addingTimeInterval(4)) == .waiting)
        #expect(await outbox.flush(to: server, now: start.addingTimeInterval(5)) == .failed(retryIn: .seconds(10)))
        #expect(await outbox.flush(to: server, force: true, now: start.addingTimeInterval(6)) == .failed(retryIn: .seconds(20)))
        for _ in 0..<6 { _ = await outbox.flush(to: server, force: true, now: start) }
        #expect(await outbox.flush(to: server, force: true, now: start) == .failed(retryIn: .seconds(300)))
        #expect(fake.requests.count == 10)
        #expect(await outbox.pending.count == 1)
    }

    @Test func aSignedOffPhoneSaysSo() async {
        let outbox = Outbox(file: nil)
        await outbox.add("game.add", game)
        let outcome = await outbox.flush(to: Server(device: device, transport: FakeTransport(.init(status: 401))))
        #expect(outcome == .signedOff)
    }

    @Test func bigOutboxesGoInBatches() async throws {
        let outbox = Outbox(file: nil)
        for _ in 0..<(Outbox.batchSize + 3) { await outbox.add("game.add", game) }
        let fake = FakeTransport(answer(""))
        #expect(await outbox.flush(to: Server(device: device, transport: fake)) == .sent(etag: #""ab12-3f-42""#, more: true))
        let body = try JSONDecoder().decode([String: [JSONValue]].self, from: try #require(fake.requests.first?.httpBody))
        #expect(body["ops"]?.count == Outbox.batchSize)
    }

    @Test func confirmDropsOnlyWhatTheReadModelHas() async {
        let outbox = Outbox(file: nil)
        let first = await outbox.add("game.add", game)
        let fake = FakeTransport(answer(#"{"id": "\#(first.id)", "ok": true}"#, seq: 42))
        _ = await outbox.flush(to: Server(device: device, transport: fake))
        let waiting = await outbox.add("game.add", game)
        await outbox.confirm(etag: #""ab12-3f-41-zstd""#)  // an older read model: keep it applied
        #expect(await outbox.ops.map(\.id) == [first.id, waiting.id])
        await outbox.confirm(etag: #""ab12-3f-42-zstd""#)
        #expect(await outbox.ops.map(\.id) == [waiting.id])  // pending ops never go this way
    }

    @Test func undoDropsAWaitingOpAndTakesBackASentOne() async {
        let outbox = Outbox(file: nil)
        let waiting = await outbox.add("game.add", game)
        #expect(await outbox.undo(waiting) == nil)
        #expect(await outbox.ops.isEmpty)

        let sent = await outbox.add("game.add", game)
        _ = await outbox.flush(to: Server(device: device, transport: FakeTransport(answer(#"{"id": "\#(sent.id)", "ok": true}"#))))
        let opposite = await outbox.undo(sent)
        #expect(opposite?.type == "game.delete")
        #expect(opposite?.payload == .object(["deck": .string("meren"), "id": .string("g1")]))
        #expect(await outbox.pending.map(\.id) == [opposite?.id])
    }

    @Test func inverses() {
        func inverse(_ type: String, _ payload: [String: JSONValue]) -> (String, JSONValue)? {
            Outbox.inverse(type, .object(payload)).map { ($0.type, $0.payload) }
        }
        let gamePayload: JSONValue = game
        #expect(inverse("game.delete", ["deck": .string("meren"), "id": .string("g1"), "restore": gamePayload])! == ("game.add", gamePayload))
        #expect(inverse("game.delete", ["deck": .string("meren"), "id": .string("g1")]) == nil)
        #expect(inverse("opponent.add", ["opponent": .object(["id": .string("o1")])])! == ("opponent.delete", .object(["id": .string("o1")])))
        #expect(inverse("opponent.note", ["id": .string("o1"), "note_id": .string("n1"), "text": .string("x")])!
            == ("opponent.note_delete", .object(["id": .string("o1"), "note_id": .string("n1")])))
        #expect(inverse("opponent.update", ["id": .string("o1"), "label": .string("New"), "prev": .object(["label": .string("Old")])])!
            == ("opponent.update", .object(["id": .string("o1"), "label": .string("Old")])))
        #expect(inverse("deck.flags", ["deck": .string("meren"), "pinned": .bool(true), "prev": .object(["pinned": .bool(false)])])!
            == ("deck.flags", .object(["deck": .string("meren"), "pinned": .bool(false)])))
        #expect(inverse("deck.pin_order", ["slugs": .array([.string("b"), .string("a")]), "prev": .array([.string("a"), .string("b")])])!
            == ("deck.pin_order", .object(["slugs": .array([.string("a"), .string("b")])])))
        #expect(inverse("deck.pin_order", ["slugs": .array([]), "prev": .array([])]) == nil)
        #expect(inverse("collection.add", ["entry": .object(["name": .string("Sol Ring"), "qty": .int(2)])])!
            == ("collection.add", .object(["entry": .object(["name": .string("Sol Ring"), "qty": .int(-2)])])))
        let entry: JSONValue = .object(["id": .string("c1"), "name": .string("Sol Ring"), "qty": .int(1)])
        #expect(inverse("collection.update", ["id": .string("c1"), "qty": .int(0), "restore": entry])! == ("collection.add", .object(["entry": entry])))
        #expect(inverse("collection.update", ["id": .string("c1"), "foil": .bool(true), "prev": .object(["foil": .bool(false)])])!
            == ("collection.update", .object(["id": .string("c1"), "foil": .bool(false)])))
        #expect(inverse("deck.edit", ["deck": .string("meren")]) == nil)
    }
}
