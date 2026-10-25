import ConclaveCore
import Foundation
import Observation
import UIKit

/// What the whole app shares: whether this phone is paired, with which server, and the decks,
/// opponents and games it last got from there.
@MainActor @Observable
final class AppModel {
    private(set) var device: Device?
    /// The read model: the saved copy at once, then whatever `refresh()` brings. nil before the first download.
    private(set) var library: ReadModel?
    /// Why the last update failed (offline, server error); nil once one worked.
    private(set) var problem: String?
    /// Why the phone is no longer paired, when the PC signed it off; shown on the welcome screen.
    private(set) var notice: String?
    private let store: any DeviceStore
    private let cache: ReadModelCache?
    private let transport: any Transport

    init(store: any DeviceStore, cache: ReadModelCache?, transport: any Transport) {
        self.store = store
        self.cache = cache
        self.transport = transport
        device = store.load()
        library = cache?.load()?.model
    }

    /// A scanned or typed pairing link or code. Throws what `Connection.message(for:)` explains.
    func pair(_ text: String, server: String = "") async throws {
        device = try await Connection.pair(text, server: server, name: UIDevice.current.model, store: store, transport: transport)
        notice = nil
        await refresh()
    }

    /// Fetches a newer read model; goes back to the welcome screen when the PC signed this phone off.
    func refresh() async {
        guard let device, let cache else { return }
        let outcome = await Connection.refresh(device, store: store, cache: cache, transport: transport)
        guard self.device?.id == device.id else { return } // signed out or paired again meanwhile
        switch outcome {
        case .changed(let model):
            library = model
            problem = nil
        case .unchanged:
            problem = nil
        case .failed(let message):
            problem = message
        case .signedOff:
            self.device = nil
            library = nil
            notice = ServerError.signedOff.message
        }
    }

    func signOff() async {
        guard let device else { return }
        await Connection.signOff(device, store: store, transport: transport)
        cache?.clear()
        self.device = nil
        library = nil
        problem = nil
    }
}

extension AppModel {
    /// The screen the CI screenshots open (`CONCLAVE_SCREEN`, scripts/screenshots.sh); nil in normal use.
    static let startScreen = ProcessInfo.processInfo.environment["CONCLAVE_SCREEN"]
    /// Screens that show the made-up account in `demo.json`.
    static let demoScreens: Set = ["decks", "deck", "rule0", "opponents", "opponent"]

    /// The real app keeps the device in the Keychain and the decks in Application Support (not Caches:
    /// iOS may empty those); a screenshot starts from a made-up state instead.
    static func launch() -> AppModel {
        let transport = URLSession.conclave()
        guard let screen = startScreen else {
            let folder = URL.applicationSupportDirectory.appending(path: "ReadModel")
            return AppModel(store: KeychainDeviceStore(), cache: ReadModelCache(folder: folder), transport: transport)
        }
        if demoScreens.contains(screen) {
            let model = AppModel(store: MemoryDeviceStore(.sample), cache: nil, transport: transport)
            model.library = demo
            return model
        }
        let model = AppModel(store: MemoryDeviceStore(), cache: nil, transport: transport)
        if screen == "signed-off" { model.notice = ServerError.signedOff.message }
        return model
    }

    /// The made-up account (scripts/make_demo.py writes it from the web app's demo).
    static let demo: ReadModel? = {
        guard let url = Bundle.main.url(forResource: "demo", withExtension: "json"), let data = try? Data(contentsOf: url)
        else { return nil }
        return try? ReadModel.decode(data)
    }()
}

extension Device {
    static let sample = Device(
        server: URL(string: "https://conclave-cloud.duckdns.org")!, token: "", id: "sample", name: "iPhone", serverID: "sample"
    )
}
