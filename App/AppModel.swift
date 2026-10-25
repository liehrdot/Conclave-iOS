import ConclaveCore
import Foundation
import Observation
import UIKit

/// What the whole app shares: whether this phone is paired, and with which server.
@MainActor @Observable
final class AppModel {
    private(set) var device: Device?
    private let store: any DeviceStore
    private let transport: any Transport

    init(store: any DeviceStore, transport: any Transport) {
        self.store = store
        self.transport = transport
        device = store.load()
    }

    /// A scanned or typed pairing link or code. Throws what `Connection.message(for:)` explains.
    func pair(_ text: String, server: String = "") async throws {
        device = try await Connection.pair(text, server: server, name: UIDevice.current.model, store: store, transport: transport)
    }

    func signOff() async {
        guard let device else { return }
        await Connection.signOff(device, store: store, transport: transport)
        self.device = nil
    }
}

extension AppModel {
    /// The screen the CI screenshots open (`CONCLAVE_SCREEN`, scripts/screenshots.sh); nil in normal use.
    static let startScreen = ProcessInfo.processInfo.environment["CONCLAVE_SCREEN"]

    /// The real app keeps the device in the Keychain; a screenshot starts from a made-up state instead.
    static func launch() -> AppModel {
        switch startScreen {
        case nil: AppModel(store: KeychainDeviceStore(), transport: URLSession.conclave())
        case "paired": AppModel(store: MemoryDeviceStore(.sample), transport: URLSession.conclave())
        default: AppModel(store: MemoryDeviceStore(), transport: URLSession.conclave())
        }
    }
}

extension Device {
    static let sample = Device(
        server: URL(string: "https://conclave-cloud.duckdns.org")!, token: "", id: "sample", name: "iPhone", serverID: "sample"
    )
}
