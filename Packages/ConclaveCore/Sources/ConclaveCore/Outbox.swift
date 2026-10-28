import Foundation

/// One change made on the phone (a game logged, an opponent edited), on its way to the server.
/// Mirrors the entries of `state.ops` in the PWA's `data.js`; the wire format is in docs/app-api.md.
public struct PendingOp: Codable, Equatable, Sendable, Identifiable {
    public enum Status: String, Codable, Sendable {
        /// Waiting to be sent, or sent without an answer yet.
        case pending
        /// The server applied it; it stays until a read model contains it (`Outbox.confirm`).
        case sent
        /// The server refused it for good; `error` says why, in German (the server's language).
        case failed
    }

    public var id: String
    public var type: String
    public var payload: JSONValue
    /// When it happened on the phone, ISO 8601 (`2026-10-10T20:00:00+00:00`).
    public var at: String
    public var status: Status
    /// The `etag` of the answer that applied it.
    public var ack: String?
    public var error: String?

    public init(id: String = PendingOp.newID(), type: String, payload: JSONValue, at: String = PendingOp.now(), status: Status = .pending) {
        self.id = id
        self.type = type
        self.payload = payload
        self.at = at
        self.status = status
    }

    /// 12 hex characters, like `uid()` in the PWA's `util.js`. The server remembers applied ids, so a
    /// batch sent twice (the answer got lost) changes nothing the second time.
    public static func newID() -> String {
        (0..<6).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
    }

    /// Now, as `nowIso()` in the PWA writes it: seconds, `+00:00`.
    public static func now(_ date: Date = .now) -> String {
        var style = Date.ISO8601FormatStyle(timeZone: .gmt)
        style = style.year().month().day().time(includingFractionalSeconds: false).timeZone(separator: .omitted)
        return date.formatted(style).replacingOccurrences(of: "Z", with: "+00:00")
    }
}

/// What the server said to one batch: `POST /api/app/ops` → `{"results": [...], "etag"}`.
public struct OpsAnswer: Decodable, Equatable, Sendable {
    public struct Result: Decodable, Equatable, Sendable {
        public var id: String
        public var ok: Bool
        public var error: String?
        /// Not applied because the server was busy: send it again later.
        public var retry: Bool?
    }

    public var results: [Result]
    public var etag: String
}

/// How a call to `Outbox.flush` went.
public enum FlushOutcome: Equatable, Sendable {
    /// Nothing waits to be sent.
    case nothing
    /// A send is already running, or the last failure's backoff hasn't passed.
    case waiting
    /// A batch reached the server; `more` when ops are still waiting behind it (send again at once).
    case sent(etag: String, more: Bool)
    /// The server couldn't be reached or failed; the ops stay and the next try waits `retryIn`.
    case failed(retryIn: Duration)
    /// The PC signed this phone off: the app forgets the device (like any other 401).
    case signedOff
}

/// The changes the phone made that the server hasn't confirmed yet, kept on disk so none is lost
/// when the app ends or the phone is offline for days. Mirrors `op()`, `flush()`, `undo()` and the
/// outbox part of `refresh()` in the PWA's `data.js`.
///
/// The rule from docs/app-api.md: an op stays in the outbox after a successful send, until a read
/// model arrives whose seq covers the answer's etag (`confirm`). Dropping it earlier makes the change
/// flicker away and back; never dropping it was Conclave PR #5's bug.
public actor Outbox {
    /// At most this many ops per request (the server takes 100; the web app sends 50).
    public static let batchSize = 50
    /// The first wait after a failure; it doubles each time up to `maxBackoff` (the web app's 5 s → 5 min).
    public static let firstBackoff: Duration = .seconds(5)
    public static let maxBackoff: Duration = .seconds(300)

    public private(set) var ops: [PendingOp]
    /// nil keeps the outbox in memory only (the demo, tests).
    private let file: URL?
    private var sending = false
    private var backoff: Duration = .zero
    private var nextTry: Date = .distantPast

    public init(file: URL?) {
        self.file = file
        if let file, let data = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode([PendingOp].self, from: data) {
            ops = saved
        } else {
            ops = []
        }
    }

    public var pending: [PendingOp] { ops.filter { $0.status == .pending } }
    public var failed: [PendingOp] { ops.filter { $0.status == .failed } }

    /// Queues a change; the app sends it with `flush(to:force: true)` right after.
    @discardableResult
    public func add(_ type: String, _ payload: JSONValue) -> PendingOp {
        let op = PendingOp(type: type, payload: payload)
        ops.append(op)
        save()
        return op
    }

    /// Sends the oldest waiting ops in one batch. Without `force` it respects the backoff after a
    /// failure (the timer's call); `force` is for a fresh op, the app coming back, or the network
    /// returning. Ops the server refused for good become `failed`; busy ones (`retry`) stay pending.
    public func flush(to server: Server, force: Bool = false, now: Date = .now) async -> FlushOutcome {
        let waiting = pending
        if waiting.isEmpty { return .nothing }
        if sending || (!force && now < nextTry) { return .waiting }
        sending = true  // before the await: an actor lets other calls in while this one waits
        defer { sending = false }
        let batch = Array(waiting.prefix(Self.batchSize))
        do {
            let answer = try await server.send(batch)
            record(answer)
            backoff = .zero
            nextTry = .distantPast
            return .sent(etag: answer.etag, more: waiting.count > batch.count)
        } catch ServerError.signedOff {
            return .signedOff
        } catch {
            backoff = backoff == .zero ? Self.firstBackoff : min(backoff * 2, Self.maxBackoff)
            nextTry = now.addingTimeInterval(backoff.seconds)
            return .failed(retryIn: backoff)
        }
    }

    /// Takes in one batch's results: applied → `sent` with the answer's etag, refused → `failed`.
    func record(_ answer: OpsAnswer) {
        for result in answer.results {
            guard let index = ops.firstIndex(where: { $0.id == result.id }) else { continue }
            if result.ok {
                ops[index].status = .sent
                ops[index].ack = answer.etag
            } else if result.retry != true {
                ops[index].status = .failed
                ops[index].error = result.error
            }
        }
        save()
    }

    /// A read model with this etag arrived: the sent ops it contains can go.
    public func confirm(etag: String) {
        let have = ETag.seq(etag)
        let before = ops.count
        ops.removeAll { $0.status == .sent && ETag.seq($0.ack) <= have }
        if ops.count != before { save() }
    }

    /// Takes a change back. Still waiting → it is simply dropped, and nil comes back. Already sent →
    /// its opposite is queued (`inverse`) and returned, for the app to send. nil too when the op has
    /// no opposite (an old game deleted without `restore`).
    @discardableResult
    public func undo(_ op: PendingOp) -> PendingOp? {
        if let index = ops.firstIndex(where: { $0.id == op.id }), ops[index].status != .sent {
            ops.remove(at: index)
            save()
            return nil
        }
        guard let opposite = Self.inverse(op.type, op.payload) else { return nil }
        return add(opposite.type, opposite.payload)
    }

    /// Forgets one op, e.g. a failed one the person dismissed.
    public func drop(id: String) {
        ops.removeAll { $0.id == id }
        save()
    }

    /// Forgets everything, when the phone is signed off.
    public func clear() {
        ops = []
        if let file { try? FileManager.default.removeItem(at: file) }
    }

    /// The operation that takes another one back. Mirrors `INVERSE` in the PWA's `data.js`.
    public static func inverse(_ type: String, _ payload: JSONValue) -> (type: String, payload: JSONValue)? {
        func with(_ base: [String: JSONValue], _ extra: JSONValue?) -> JSONValue {
            .object(base.merging(extra?.object ?? [:]) { first, _ in first })
        }
        switch type {
        case "game.add":
            guard let game = payload["game"], let deck = game["deck"], let id = game["id"] else { return nil }
            return ("game.delete", .object(["deck": deck, "id": id]))
        case "game.delete":
            guard let restore = payload["restore"] else { return nil }
            return ("game.add", restore)
        case "opponent.add":
            guard let id = payload["opponent"]?["id"] else { return nil }
            return ("opponent.delete", .object(["id": id]))
        case "opponent.note":
            guard let id = payload["id"], let note = payload["note_id"] else { return nil }
            return ("opponent.note_delete", .object(["id": id, "note_id": note]))
        case "opponent.update":
            guard let id = payload["id"], let prev = payload["prev"] else { return nil }
            return ("opponent.update", with(["id": id], prev))
        case "deck.flags":
            guard let deck = payload["deck"], let prev = payload["prev"] else { return nil }
            return ("deck.flags", with(["deck": deck], prev))
        case "deck.edit":  // the app's own `prev` (`DeckEdit.add`); the PWA can't take a deck edit back
            guard let deck = payload["deck"], let prev = payload["prev"] else { return nil }
            return ("deck.edit", with(["deck": deck], prev))
        case "deck.pin_order":
            guard let prev = payload["prev"], prev.array?.isEmpty == false else { return nil }
            return ("deck.pin_order", .object(["slugs": prev]))
        case "collection.add":
            guard var entry = payload["entry"]?.object, let qty = entry["qty"]?.int else { return nil }
            entry["qty"] = .int(-qty)
            return ("collection.add", .object(["entry": .object(entry)]))
        case "collection.update":
            if let restore = payload["restore"] { return ("collection.add", .object(["entry": restore])) }
            guard let id = payload["id"], let prev = payload["prev"] else { return nil }
            return ("collection.update", with(["id": id], prev))
        default:
            return nil
        }
    }

    private func save() {
        guard let file else { return }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(ops).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            // the ops stay in memory and are written with the next change
        }
    }
}

extension Duration {
    /// The duration in seconds, for `Date.addingTimeInterval`.
    var seconds: TimeInterval {
        let (whole, fraction) = components
        return TimeInterval(whole) + TimeInterval(fraction) / 1e18
    }
}

extension Server {
    /// Sends ops in one batch: `POST /api/app/ops` with `{"ops": [{id, type, payload, at}]}`.
    public func send(_ ops: [PendingOp]) async throws -> OpsAnswer {
        struct Wire: Encodable { let id: String; let type: String; let payload: JSONValue; let at: String }
        var request = request("api/app/ops")
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["ops": ops.map { Wire(id: $0.id, type: $0.type, payload: $0.payload, at: $0.at) }])
        return try Self.decode(OpsAnswer.self, try await Self.send(request, transport: transport, claiming: false))
    }
}
