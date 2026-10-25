import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import ConclaveCore

@Suite struct DescribeTests {
    let device = Device(server: URL(string: "https://sync.example.org")!, token: "tok", id: "dev1", name: "iPhone", serverID: "ab12")
    static let settings = #"{"configured": true, "model": "claude-haiku-5-5", "from_env": false, "key_hint": "…a1b2", "models": [{"id": "claude-haiku-5-5", "label": "Claude Haiku 5.5", "note": "Schnell", "cost": "≈ 0,03 Cent"}]}"#

    func body(_ request: URLRequest?) throws -> [String: JSONValue] {
        try JSONDecoder().decode([String: JSONValue].self, from: try #require(request?.httpBody))
    }

    @Test func aDescriptionBecomesAQuery() async throws {
        let fake = FakeTransport(.init(body: #"{"query": "o:\"draw a card\" t:creature id<=bg -id:c f:commander", "broader": "", "explain": "Zieht Karten", "cached": true}"#))
        let answer = try await Server(device: device, transport: fake).describe("draws when a creature dies", colors: ["B", "G"], types: ["creature"])
        #expect(answer.query.hasPrefix("o:\"draw a card\""))
        #expect(answer.cached)
        let request = try #require(fake.requests.first)
        #expect(request.url?.absoluteString == "https://sync.example.org/api/app/cards/describe")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer tok")
        #expect(try body(request) == ["text": .string("draws when a creature dies"), "colors": .array([.string("B"), .string("G")]),
                                      "types": .array([.string("creature")])])
    }

    @Test func notSetUpIsTold() async {
        do {
            _ = try await Server(device: device, transport: FakeTransport(.init(status: 409, body: #"{"detail": "noch nicht eingerichtet"}"#))).describe("x")
            Issue.record("no error")
        } catch let error as ServerError {
            #expect(error.needsSetup)
            #expect(!ServerError.offline.needsSetup)
        } catch {
            Issue.record("wrong error \(error)")
        }
    }

    @Test func theSettingsNeverHoldTheKeyAndOnlyChangedFieldsAreSent() async throws {
        let fake = FakeTransport(.init(body: Self.settings), .init(body: Self.settings))
        let server = Server(device: device, transport: fake)
        let settings = try await server.aiSettings()
        #expect(settings.configured)
        #expect(settings.keyHint == "…a1b2")
        #expect(settings.models.map(\.label) == ["Claude Haiku 5.5"])
        _ = try await server.setAI(model: "claude-haiku-5-5")
        let put = fake.requests[1]
        #expect(put.httpMethod == "PUT")
        #expect(try body(put) == ["model": .string("claude-haiku-5-5")])  // no "key": the stored key stays
    }
}
