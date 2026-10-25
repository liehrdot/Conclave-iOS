import ConclaveCore
import Foundation
import Observation
import UIKit

/// What the whole app shares: whether this phone is paired, and with which server.
@MainActor @Observable
final class AppModel {
    private(set) var device: Device?
    /// Why the phone is no longer paired, when the PC signed it off; shown on the welcome screen.
    private(set) var notice: String?
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
        notice = nil
    }

    /// Asks the server whether the PC signed this phone off, and goes back to the welcome screen if so.
    func checkStillPaired() async {
        guard let device, !(await Connection.stillPaired(device, store: store, transport: transport)),
              self.device?.id == device.id else { return }
        self.device = nil
        notice = ServerError.signedOff.message
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
        let model = switch startScreen {
        case nil: AppModel(store: KeychainDeviceStore(), transport: URLSession.conclave())
        case "paired": AppModel(store: MemoryDeviceStore(.sample), transport: URLSession.conclave())
        default: AppModel(store: MemoryDeviceStore(), transport: URLSession.conclave())
        }
        if startScreen == "signed-off" { model.notice = ServerError.signedOff.message }
        return model
    }
}

extension Device {
    static let sample = Device(
        server: URL(string: "https://conclave-cloud.duckdns.org")!, token: "", id: "sample", name: "iPhone", serverID: "sample"
    )
}
