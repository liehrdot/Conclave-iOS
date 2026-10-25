import Foundation
import Testing
@testable import ConclaveCore

@Suite struct ReadModelCacheTests {
    let cache = ReadModelCache(folder: FileManager.default.temporaryDirectory.appending(path: "readmodel-\(UUID().uuidString)"))
    let server = { (fake: FakeTransport) in
        Server(device: Device(server: URL(string: "https://sync.example.org")!, token: "t", id: "d", name: "n", serverID: "s"), transport: fake)
    }
    let model = try! #require(ReadModelTests.models.first)

    @Test func savesWhatTheServerSentAndSendsItsTagNextTime() async throws {
        #expect(cache.load() == nil)
        let first = FakeTransport(.init(body: String(decoding: model, as: UTF8.self), headers: ["ETag": "\"ab-1-7\""]))
        let got = try #require(try await cache.refresh(from: server(first)))
        #expect(!got.decks.isEmpty)
        #expect(cache.load()?.etag == "\"ab-1-7\"")
        #expect(cache.load()?.model == got)

        let again = FakeTransport(.init(status: 304))
        #expect(try await cache.refresh(from: server(again)) == nil)
        #expect(again.requests.first?.value(forHTTPHeaderField: "If-None-Match") == "\"ab-1-7\"")
        #expect(cache.load()?.model == got)
        cache.clear()
        #expect(cache.load() == nil)
    }

    @Test func aFailureOrABrokenBodyKeepsTheSavedCopy() async throws {
        try cache.save(model, etag: "old")
        let offline = FakeTransport()
        offline.failure = URLError(.notConnectedToInternet)
        await #expect(throws: ServerError.offline) { try await cache.refresh(from: server(offline)) }
        await #expect(throws: (any Error).self) { try await cache.refresh(from: server(FakeTransport(.init(body: "not json")))) }
        #expect(cache.load()?.etag == "old")
        cache.clear()
    }
}
