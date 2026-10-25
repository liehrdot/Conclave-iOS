import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Sends one request and hands back the answer. `URLSession` is the real one; tests pass a fake,
/// so the server calls are checked without a network.
public protocol Transport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

extension URLSession: Transport {
    /// A session for the sync server: no URL cache (the app keeps the read model itself and asks
    /// with `If-None-Match`, a second cache would only hide the server's 304) and no cookies (the
    /// token goes in a header).
    public static func conclave() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.timeoutIntervalForRequest = 20
        return URLSession(configuration: config)
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ServerError.offline }
        return (data, http)
    }
}

/// This phone as the sync server knows it, from `POST /api/pair/claim`. The token is shown only
/// once, so the app keeps it in the Keychain.
public struct Device: Codable, Equatable, Sendable {
    public let server: URL
    public let token: String
    public let id: String
    public let name: String
    /// The server's id: another one means another or a restored server (docs/app-api.md).
    public let serverID: String

    public init(server: URL, token: String, id: String, name: String, serverID: String) {
        self.server = server
        self.token = token
        self.id = id
        self.name = name
        self.serverID = serverID
    }
}

/// What can go wrong talking to the server, in the words the app shows.
public enum ServerError: Error, Equatable, Sendable {
    /// 403 on claim: the code is wrong, used or older than 15 minutes.
    case wrongCode
    /// 429: too many wrong codes (pairing) or searches; try again in a few minutes.
    case tooManyTries
    /// 401 anywhere: the device was signed off on the PC. Forget the token and the data.
    case signedOff
    /// No answer at all: no network, server down, timeout.
    case offline
    /// Anything else, with the server's own message (German) when it sent one.
    case failed(status: Int, message: String)
}

/// `GET /api/app/status`: cheap, polled while the app is open.
public struct ServerStatus: Decodable, Equatable, Sendable {
    public struct PC: Decodable, Equatable, Sendable {
        public let name: String
        public let online: Bool
        /// Unix time of the PC's last request.
        public let lastSeen: Double?

        public init(name: String, online: Bool, lastSeen: Double?) {
            self.name = name
            self.online = online
            self.lastSeen = lastSeen
        }

        /// When the PC was last seen, on the phone's clock: the server's age of it (`now - lastSeen`)
        /// from `received`, so a phone whose clock is off still says "2 hours ago" right.
        public func lastSeen(now serverNow: Double?, received: Date = .now) -> Date? {
            guard let lastSeen else { return nil }
            guard let serverNow else { return Date(timeIntervalSince1970: lastSeen) }
            return received.addingTimeInterval(-max(0, serverNow - lastSeen))
        }
    }

    public let etag: String
    public let pcs: [PC]
    /// The server's clock (Unix time) when it answered.
    public let now: Double?
}

/// The answer of `GET /api/app/data`.
public enum ReadModelAnswer: Equatable, Sendable {
    /// 304: the copy the app has is still current.
    case unchanged
    /// The new read model, as raw JSON (the app saves it as it is and decodes it off the main thread).
    case changed(Data, etag: String)
}

/// The sync server's phone API (docs/app-api.md in Conclave). Mirrors `api()`, `connect()` and
/// `refresh()` in the PWA's `data.js`.
public struct Server: Sendable {
    public let device: Device
    let transport: any Transport

    public init(device: Device, transport: any Transport) {
        self.device = device
        self.transport = transport
    }

    /// Redeems a pairing code: `POST /api/pair/claim` with `kind: "phone"`.
    ///
    /// The device keeps the address the app reached (`pairing.server`), not the `server` field of the
    /// answer: that one is only as right as the server's configured public URL.
    public static func claim(_ pairing: Pairing, name: String, transport: any Transport) async throws -> Device {
        struct Claimed: Decodable { let token: String; let deviceId: String; let name: String; let serverId: String }
        var request = URLRequest(url: pairing.server.appending(path: "api/pair/claim"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["code": pairing.code, "name": name, "kind": "phone"])
        let data = try await send(request, transport: transport, claiming: true)
        let got = try decode(Claimed.self, data)
        return Device(server: pairing.server, token: got.token, id: got.deviceId, name: got.name, serverID: got.serverId)
    }

    /// The read model; with `etag` (the tag of the copy the app has) an unchanged model costs no body.
    public func readModel(etag: String?) async throws -> ReadModelAnswer {
        var request = request("api/app/data")
        if let etag, !etag.isEmpty { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        let (data, response) = try await Self.exchange(request, transport: transport)
        if response.statusCode == 304 { return .unchanged }
        try Self.check(response, data, claiming: false)
        return .changed(data, etag: response.value(forHTTPHeaderField: "ETag") ?? "")
    }

    public func status() async throws -> ServerStatus {
        try Self.decode(ServerStatus.self, try await Self.send(request("api/app/status"), transport: transport, claiming: false))
    }

    /// Signs this phone off ("Sign out"): `DELETE /api/devices/<own id>`.
    public func signOff() async throws {
        var request = request("api/devices/\(device.id)")
        request.httpMethod = "DELETE"
        _ = try await Self.send(request, transport: transport, claiming: false)
    }

    func request(_ path: String) -> URLRequest {
        var request = URLRequest(url: device.server.appending(path: path))
        request.setValue("Bearer \(device.token)", forHTTPHeaderField: "Authorization")
        return request
    }

    static func send(_ request: URLRequest, transport: any Transport, claiming: Bool) async throws -> Data {
        let (data, response) = try await exchange(request, transport: transport)
        try check(response, data, claiming: claiming)
        return data
    }

    static func exchange(_ request: URLRequest, transport: any Transport) async throws -> (Data, HTTPURLResponse) {
        do { return try await transport.send(request) }
        catch let error as ServerError { throw error }
        catch { throw ServerError.offline }
    }

    /// Turns an error status into a `ServerError`; 2xx passes.
    static func check(_ response: HTTPURLResponse, _ data: Data, claiming: Bool) throws {
        switch response.statusCode {
        case 200..<300: return
        case 401: throw ServerError.signedOff
        case 403 where claiming: throw ServerError.wrongCode
        case 429: throw ServerError.tooManyTries
        default:
            // FastAPI answers {"detail": "…"}; validation errors carry a list there instead
            struct Detail: Decodable { let detail: String }
            let message = (try? JSONDecoder().decode(Detail.self, from: data))?.detail ?? ""
            throw ServerError.failed(status: response.statusCode, message: message)
        }
    }

    static func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do { return try decoder.decode(type, from: data) }
        catch { throw ServerError.failed(status: 200, message: "") }
    }
}
