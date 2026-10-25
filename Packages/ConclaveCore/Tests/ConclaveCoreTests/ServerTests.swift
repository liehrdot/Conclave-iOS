import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import ConclaveCore

/// A server that answers from a list and remembers what it was asked.
final class FakeTransport: Transport, @unchecked Sendable {
    struct Answer { var status = 200; var body = ""; var headers: [String: String] = [:] }
    private let lock = NSLock()
    private var answers: [Answer]
    private(set) var requests: [URLRequest] = []
    var failure: (any Error)?

    init(_ answers: Answer...) { self.answers = answers }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try lock.withLock {
            requests.append(request)
            if let failure { throw failure }
            let answer = answers.isEmpty ? Answer(status: 500) : answers.removeFirst()
            let response = HTTPURLResponse(url: request.url!, statusCode: answer.status, httpVersion: nil, headerFields: answer.headers)!
            return (Data(answer.body.utf8), response)
        }
    }
}

@Suite struct ServerTests {
    let pairing = Pairing.parse("https://sync.example.org/koppeln#ABCD-EFGH")!
    let device = Device(server: URL(string: "https://sync.example.org")!, token: "tok", id: "dev1", name: "Flo's iPhone", serverID: "ab12")

    @Test func claimRedeemsTheCodeAsAPhone() async throws {
        let fake = FakeTransport(.init(body: #"{"token": "tok", "device_id": "dev1", "name": "Flo's iPhone", "server": "http://wrong", "server_id": "ab12"}"#))
        let got = try await Server.claim(pairing, name: "Flo's iPhone", transport: fake)
        #expect(got == device)  // the address the app reached, not the answer's "server"
        let request = try #require(fake.requests.first)
        #expect(request.url?.absoluteString == "https://sync.example.org/api/pair/claim")
        #expect(request.httpMethod == "POST")
        let body = try JSONDecoder().decode([String: String].self, from: try #require(request.httpBody))
        #expect(body == ["code": "ABCD-EFGH", "name": "Flo's iPhone", "kind": "phone"])
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func claimErrors() async {
        await #expect(throws: ServerError.wrongCode) {
            try await Server.claim(pairing, name: "x", transport: FakeTransport(.init(status: 403)))
        }
        await #expect(throws: ServerError.tooManyTries) {
            try await Server.claim(pairing, name: "x", transport: FakeTransport(.init(status: 429)))
        }
        await #expect(throws: ServerError.failed(status: 200, message: "")) {
            try await Server.claim(pairing, name: "x", transport: FakeTransport(.init(body: "<html>")))
        }
    }

    @Test func readModelSendsTheTokenAndTheTag() async throws {
        let fake = FakeTransport(.init(body: #"{"version": 1}"#, headers: ["ETag": #""ab12-3f-42-zstd""#]), .init(status: 304))
        let server = Server(device: device, transport: fake)
        #expect(try await server.readModel(etag: nil) == .changed(Data(#"{"version": 1}"#.utf8), etag: #""ab12-3f-42-zstd""#))
        #expect(try await server.readModel(etag: #""ab12-3f-42-zstd""#) == .unchanged)
        #expect(fake.requests[0].value(forHTTPHeaderField: "Authorization") == "Bearer tok")
        #expect(fake.requests[0].value(forHTTPHeaderField: "If-None-Match") == nil)
        // sent back exactly as it came: the server (behind Caddy) compares the whole header
        #expect(fake.requests[1].value(forHTTPHeaderField: "If-None-Match") == #""ab12-3f-42-zstd""#)
        #expect(fake.requests[1].url?.absoluteString == "https://sync.example.org/api/app/data")
    }

    @Test func statusListsThePCs() async throws {
        let body = #"{"etag": "\"ab12-3f-42\"", "pcs": [{"name": "Desk", "online": true, "last_seen": 1761386400.5}], "device": {"id": "dev1", "name": "x"}, "now": 1761386401}"#
        let status = try await Server(device: device, transport: FakeTransport(.init(body: body))).status()
        #expect(status.etag == #""ab12-3f-42""#)
        #expect(status.pcs == [.init(name: "Desk", online: true, lastSeen: 1761386400.5)])
        #expect(status.now == 1761386401)
    }

    @Test func lastSeenUsesTheServersClock() {
        let received = Date(timeIntervalSince1970: 1_000_000)  // the phone's clock, far off the server's
        let pc = ServerStatus.PC(name: "Desk", online: false, lastSeen: 1761386400)
        #expect(pc.lastSeen(now: 1761386400 + 7200, received: received) == received.addingTimeInterval(-7200))
        #expect(pc.lastSeen(now: nil, received: received) == Date(timeIntervalSince1970: 1761386400))
        #expect(ServerStatus.PC(name: "New", online: false, lastSeen: nil).lastSeen(now: 1, received: received) == nil)
        // a PC "seen" after the server's now (clock skew between requests) is seen just now, never in the future
        #expect(pc.lastSeen(now: 1761386000, received: received) == received)
    }

    @Test func aSignedOffDeviceIsTold() async {
        let server = Server(device: device, transport: FakeTransport(.init(status: 401)))
        await #expect(throws: ServerError.signedOff) { try await server.readModel(etag: nil) }
    }

    @Test func otherErrorsCarryTheServersMessage() async {
        let server = Server(device: device, transport: FakeTransport(.init(status: 503, body: #"{"detail": "Gerade beschäftigt"}"#)))
        await #expect(throws: ServerError.failed(status: 503, message: "Gerade beschäftigt")) { try await server.status() }
        let plain = Server(device: device, transport: FakeTransport(.init(status: 500, body: "oops")))
        await #expect(throws: ServerError.failed(status: 500, message: "")) { try await plain.readModel(etag: "") }
    }

    @Test func noAnswerIsOffline() async {
        let fake = FakeTransport()
        fake.failure = URLError(.notConnectedToInternet)
        await #expect(throws: ServerError.offline) { try await Server(device: device, transport: fake).status() }
        fake.failure = ServerError.signedOff
        await #expect(throws: ServerError.signedOff) { try await Server(device: device, transport: fake).status() }
    }

    @Test func signOffDeletesTheOwnDevice() async throws {
        let fake = FakeTransport(.init(body: #"{"ok": true, "self": true}"#))
        try await Server(device: device, transport: fake).signOff()
        #expect(fake.requests[0].httpMethod == "DELETE")
        #expect(fake.requests[0].url?.absoluteString == "https://sync.example.org/api/devices/dev1")
    }

    @Test func aDeviceRoundTrips() throws {
        let again = try JSONDecoder().decode(Device.self, from: JSONEncoder().encode(device))
        #expect(again == device)
    }
}

@Suite struct SessionTests {
    @Test func theSessionKeepsNoCacheOrCookies() {
        let config = URLSession.conclave().configuration
        #expect(config.urlCache == nil)
        #expect(config.httpCookieStorage == nil)
    }

    @Test func aClosedPortIsOffline() async {
        // port 1 on this machine: refused at once, nothing leaves the computer
        let device = Device(server: URL(string: "http://127.0.0.1:1")!, token: "t", id: "d", name: "n", serverID: "s")
        await #expect(throws: ServerError.offline) { try await Server(device: device, transport: URLSession.conclave()).status() }
    }
}
