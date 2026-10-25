import ConclaveCore
import Foundation
import Observation
import UIKit

/// What the whole app shares: whether this phone is paired, with which server, and the decks,
/// opponents and games it last got from there.
@MainActor @Observable
final class AppModel {
    private(set) var device: Device?
    /// The read model as the screens show it: the server's copy (`base`) with this phone's own changes from
    /// the outbox applied on top (`Optimistic`). nil before the first download.
    private(set) var library: ReadModel?
    /// The phone's changes the server hasn't confirmed yet: waiting, sent, or refused (`PendingOp.Status`).
    private(set) var ops: [PendingOp] = []
    /// The read model exactly as the server sent it (raw, so keys the app doesn't know survive).
    private var base: JSONValue?
    private var outbox: Outbox
    private let outboxFile: URL?
    /// Why the last update failed (offline, server error); nil once one worked.
    private(set) var problem: String?
    /// When the server last answered a refresh (new data or "unchanged").
    private(set) var lastUpdate: Date?
    /// The PCs on the sync server, as the settings show them; nil until `loadStatus()` got an answer.
    private(set) var status: ServerStatus?
    /// When `status` arrived, on this phone's clock.
    private(set) var statusReceived: Date?
    /// The last `loadStatus()` got no answer.
    private(set) var statusFailed = false
    /// Why the phone is no longer paired, when the PC signed it off; shown on the welcome screen.
    private(set) var notice: String?
    /// The game the `saved` screenshot logs: a win with the demo's first deck.
    static let screenshotGame: JSONValue = .object([
        "game": .object(["id": .string("shot1"), "deck": .string("meren-aristocrats"), "result": .string("win"), "place": .int(1)]),
        "opponents": .array([.object(["id": .string("o-atraxa"), "commander": .string("Atraxa, Praetors' Voice"), "place": .int(2)])]),
    ])

    /// The made-up account from the welcome screen ("Try the Demo"): nothing is sent anywhere.
    var inDemo: Bool { device == .demo }
    /// Card texts and Scryfall's printings, looked up by name (the read model has only names).
    let cards: CardLibrary
    private let store: any DeviceStore
    private let cache: ReadModelCache?
    private let transport: any Transport

    init(store: any DeviceStore, cache: ReadModelCache?, transport: any Transport, cardFile: URL? = nil, outboxFile: URL? = nil) {
        cards = CardLibrary(scryfall: Scryfall(transport: transport), file: cardFile)
        self.store = store
        self.cache = cache
        self.transport = transport
        self.outboxFile = outboxFile
        outbox = Outbox(file: outboxFile)
        device = store.load()
        base = cache?.loadJSON()?.json
        library = base.flatMap { try? ReadModel.decode($0) }
        Task { await showOps() }
        // the demo stays on across launches until "Leave Demo", like the PWA's `amtisch.mode`
        if device == nil, UserDefaults.standard.bool(forKey: Self.demoKey) { showDemo() }
    }

    private static let demoKey = "demo"

    /// Opens the made-up account. It replaces nothing: pairing later starts from the welcome screen.
    func startDemo() {
        guard device == nil else { return }
        UserDefaults.standard.set(true, forKey: Self.demoKey)
        notice = nil
        showDemo()
    }

    private func showDemo() {
        device = .demo
        outbox = Outbox(file: nil)  // the demo's games live in memory only and are never sent
        ops = []
        base = Self.demoJSON
        library = Self.demo
        // never "Loading…" forever: the core tests check that demo.json decodes, this is the last guard
        problem = Self.demo == nil ? "The demo couldn't be opened." : nil
    }

    /// Back to the welcome screen, to pair with the PC.
    func leaveDemo() async {
        guard inDemo else { return }
        UserDefaults.standard.removeObject(forKey: Self.demoKey)
        device = nil
        library = nil
        base = nil
        ops = []
        outbox = Outbox(file: outboxFile)
        await cards.clear()
    }

    /// A scanned or typed pairing link or code. Throws what `Connection.message(for:)` explains.
    func pair(_ text: String, server: String = "") async throws {
        if inDemo { await leaveDemo() }
        device = try await Connection.pair(text, server: server, name: UIDevice.current.model, store: store, transport: transport)
        notice = nil
        await refresh()
    }

    /// Fetches a newer read model; goes back to the welcome screen when the PC signed this phone off.
    func refresh() async {
        guard let device, !inDemo, let cache else { return }
        let outcome = await Connection.refresh(device, store: store, cache: cache, transport: transport)
        guard self.device?.id == device.id else { return } // signed out or paired again meanwhile
        switch outcome {
        case .changed, .unchanged:
            problem = nil
            lastUpdate = .now
            // the sent ops this copy contains can go; the rest stays applied on top of it
            if let saved = cache.loadJSON() {
                base = saved.json
                await outbox.confirm(etag: saved.etag)
            }
            await showOps()
            if !(await outbox.pending.isEmpty) { await send() }
        case .failed(let message):
            problem = message
        case .signedOff:
            await forgetAccount()
            notice = ServerError.signedOff.message
        }
    }

    /// Saves a change made on the phone (a game, an opponent edit): shown at once, sent right after,
    /// and kept in the outbox until the server has it. In the demo it stays on this phone.
    /// The toast with "Undo" shows it for a few seconds.
    @discardableResult
    func save(_ type: String, _ payload: JSONValue) async -> PendingOp {
        let op = await outbox.add(type, payload)
        await showOps()
        saved = Saved(op: op, text: "\(op.summary(in: library)) saved")
        Task { await send(force: true) }
        return op
    }

    /// The change just saved, for the toast with "Undo"; nil once the toast is gone.
    var saved: Saved?

    struct Saved: Identifiable, Equatable {
        var id: String { op.id }
        let op: PendingOp
        let text: String
    }

    /// Takes a change back (the toast's "Undo"): one still waiting is simply dropped, one already sent
    /// gets its opposite sent (`Outbox.undo`, the PWA's `undo()`).
    func undo(_ op: PendingOp) async {
        saved = nil
        let opposite = await outbox.undo(op)
        await showOps()
        if opposite != nil { await send(force: true) }
    }

    /// Forgets a change the server refused, once the person has read why.
    func dismiss(_ op: PendingOp) async {
        await outbox.drop(id: op.id)
        await showOps()
    }

    /// Changes not sent yet: shown as a quiet line, never in the demo (nothing is sent there).
    var waiting: [PendingOp] { inDemo ? [] : ops.filter { $0.status == .pending } }
    /// Changes the server refused for good, with its reason.
    var refused: [PendingOp] { ops.filter { $0.status == .failed } }

    /// Sends what waits in the outbox. After a batch went through, the next read model is fetched so the
    /// server's copy replaces the guess; on a failure the outbox waits (5 s, doubling) and the next
    /// refresh tries again.
    func send(force: Bool = false) async {
        guard let device, !inDemo else { return }
        let outcome = await outbox.flush(to: Server(device: device, transport: transport), force: force)
        guard self.device?.id == device.id else { return }
        await showOps()
        switch outcome {
        case .sent(_, let more):
            if more { await send(force: true) } else { await refresh() }
        case .signedOff:
            await forgetAccount()
            notice = ServerError.signedOff.message
        case .nothing, .waiting, .failed:
            break
        }
    }

    /// Shows the outbox's ops on top of the server's copy.
    private func showOps() async {
        ops = await outbox.ops
        guard let base else { return }
        let shown = Optimistic.apply(ops, to: base)
        library = (try? ReadModel.decode(shown)) ?? library
    }

    /// The PC signed this phone off: the device, its decks and its unsent changes go.
    private func forgetAccount() async {
        device = nil
        library = nil
        base = nil
        status = nil
        await outbox.clear()
        ops = []
        await cards.clear()
    }

    /// Asks the server which PCs are there and online (`GET /api/app/status`), for the settings.
    /// A failure leaves the last answer; a 401 is noticed by the next `refresh()`.
    func loadStatus() async {
        guard let device, !inDemo else { return }
        let answer = try? await Server(device: device, transport: transport).status()
        guard self.device == device else { return }
        statusFailed = answer == nil
        if let answer {
            status = answer
            statusReceived = .now
        }
    }

    func signOff() async {
        guard let device, !inDemo else { return await leaveDemo() }
        await Connection.signOff(device, store: store, transport: transport)
        cache?.clear()
        await forgetAccount()
        problem = nil
        lastUpdate = nil
    }
}

extension AppModel {
    /// The screen the CI screenshots open (`CONCLAVE_SCREEN`, scripts/screenshots.sh); nil in normal use.
    static let startScreen = ProcessInfo.processInfo.environment["CONCLAVE_SCREEN"]
    /// Screens that show the made-up account in `demo.json`.
    static let demoScreens: Set = ["decks", "deck", "rule0", "card", "log-game", "saved", "opponents", "opponent", "edit-opponent", "cards", "settings"]

    /// The real app keeps the device in the Keychain and the decks in Application Support (not Caches:
    /// iOS may empty those); a screenshot starts from a made-up state instead.
    static func launch() -> AppModel {
        let transport = URLSession.conclave()
        guard let screen = startScreen else {
            let folder = URL.applicationSupportDirectory.appending(path: "ReadModel")
            return AppModel(store: KeychainDeviceStore(), cache: ReadModelCache(folder: folder), transport: transport,
                            cardFile: URL.applicationSupportDirectory.appending(path: "Cards/cards.json"),
                            outboxFile: URL.applicationSupportDirectory.appending(path: "Outbox/outbox.json"))
        }
        if demoScreens.contains(screen) {
            let model = AppModel(store: MemoryDeviceStore(), cache: nil, transport: transport)
            model.showDemo()
            if screen == "saved" { Task { await model.save("game.add", Self.screenshotGame) } }
            return model
        }
        let model = AppModel(store: MemoryDeviceStore(), cache: nil, transport: transport)
        if screen == "signed-off" { model.notice = ServerError.signedOff.message }
        return model
    }

    /// The made-up account (scripts/make_demo.py writes it from the web app's demo).
    static let demo: ReadModel? = demoJSON.flatMap { try? ReadModel.decode($0) }

    static let demoJSON: JSONValue? = {
        guard let url = Bundle.main.url(forResource: "demo", withExtension: "json"), let data = try? Data(contentsOf: url)
        else { return nil }
        return try? JSONDecoder().decode(JSONValue.self, from: data)
    }()
}

extension Device {
    /// The demo's stand-in device: never saved, never sent (no token).
    static let demo = Device(
        server: URL(string: "https://demo.invalid")!, token: "", id: "demo", name: "iPhone", serverID: "demo"
    )
}
