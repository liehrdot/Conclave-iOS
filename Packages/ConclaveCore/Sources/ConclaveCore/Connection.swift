import Foundation

/// Where the paired device is kept. The app's is the Keychain (the token must never sit in a plain
/// file or in backups of another phone); tests and screenshots use `MemoryDeviceStore`.
public protocol DeviceStore: Sendable {
    func load() -> Device?
    func save(_ device: Device) throws
    func clear()
}

/// A store that forgets everything when the app ends.
public final class MemoryDeviceStore: DeviceStore, @unchecked Sendable {
    private let lock = NSLock()
    private var device: Device?

    public init(_ device: Device? = nil) { self.device = device }

    public func load() -> Device? { lock.withLock { device } }
    public func save(_ device: Device) throws { lock.withLock { self.device = device } }
    public func clear() { lock.withLock { device = nil } }
}

/// Pairing this phone and signing it off again. Mirrors `connect()` and `disconnect()` in the PWA's `data.js`.
public enum Connection {
    /// Why pairing can't start, before the server is asked.
    public enum Problem: Error, Equatable, Sendable {
        /// Neither a pairing link nor a code.
        case notACode
        /// A bare code, but no server address with it.
        case needsServer
    }

    /// What the person typed or scanned → a paired, saved device.
    public static func pair(
        _ text: String, server: String = "", name: String, store: any DeviceStore, transport: any Transport
    ) async throws -> Device {
        guard let pairing = Pairing.parse(text, server: server) else {
            throw Pairing.parse(text, server: "localhost") == nil ? Problem.notACode : Problem.needsServer
        }
        let device = try await Server.claim(pairing, name: name, transport: transport)
        try store.save(device)
        return device
    }

    /// Signs this phone off on the server and forgets it here. The local part always happens: when the
    /// server can't be reached the device stays listed on the PC, where it can be removed by hand.
    public static func signOff(_ device: Device, store: any DeviceStore, transport: any Transport) async {
        try? await Server(device: device, transport: transport).signOff()
        store.clear()
    }

    /// What `refresh` found out.
    public enum Refresh: Equatable, Sendable {
        /// A newer read model, already saved.
        case changed(ReadModel)
        /// The saved one is current.
        case unchanged
        /// No answer or an error: the saved copy stays, the reason is the sentence to show.
        case failed(String)
        /// The PC signed this phone off: the device and the saved copy are forgotten.
        case signedOff
    }

    /// Fetches a newer read model into `cache`. A 401 means the PC signed this phone off (removed it
    /// from its device list): it forgets the device and the saved decks, like `data.js` does on a 401.
    /// Offline or any other error keeps both, so a phone without signal at the table keeps its decks.
    public static func refresh(
        _ device: Device, store: any DeviceStore, cache: ReadModelCache, transport: any Transport
    ) async -> Refresh {
        do {
            guard let model = try await cache.refresh(from: Server(device: device, transport: transport)) else { return .unchanged }
            return .changed(model)
        } catch ServerError.signedOff {
            // only the device that was asked: the phone may have been paired again meanwhile
            if store.load()?.id == device.id {
                store.clear()
                cache.clear()
            }
            return .signedOff
        } catch {
            return .failed(message(for: error, doing: "Couldn't update"))
        }
    }
}

extension Connection {
    /// The sentence the app shows for anything `pair` throws.
    public static func message(for error: any Error) -> String {
        message(for: error, doing: "Pairing didn't work")
    }

    /// The sentence for an error; `doing` starts the one for an error without a sentence of its own.
    static func message(for error: any Error, doing: String) -> String {
        switch error {
        case let problem as Problem: problem.message
        case let error as ServerError: error.message
        default: "\(doing). Please try again."
        }
    }
}

extension Connection.Problem {
    public var message: String {
        switch self {
        case .notACode: "That isn't a pairing link or code. On your PC: Settings › Sync › Pair a device."
        case .needsServer: "Enter your sync server's address too, or scan the QR code instead."
        }
    }
}

extension ServerError {
    /// What the app says. The server's own messages are German; they are shown as they are.
    public var message: String {
        switch self {
        case .wrongCode: "The code is wrong or has expired. Codes work once, for 15 minutes: make a new one on your PC."
        case .tooManyTries: "Too many tries. Please wait a few minutes and try again."
        case .signedOff: "This iPhone was signed off on your PC. Pair it again to continue."
        case .offline: "Can't reach the sync server. Check the connection and the address."
        case .failed(let status, let message):
            message.isEmpty ? "The sync server answered with an error (\(status))." : message
        }
    }
}
