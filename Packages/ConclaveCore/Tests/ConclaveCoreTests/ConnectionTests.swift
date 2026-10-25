import Foundation
import Testing
@testable import ConclaveCore

@Suite struct ConnectionTests {
    let claimed = #"{"token": "tok", "device_id": "dev1", "name": "iPhone", "server": "", "server_id": "ab12"}"#

    @Test func pairingSavesTheDevice() async throws {
        let store = MemoryDeviceStore()
        let fake = FakeTransport(.init(body: claimed))
        let device = try await Connection.pair("ABCD-EFGH", server: "sync.example.org", name: "iPhone", store: store, transport: fake)
        #expect(device.server.absoluteString == "https://sync.example.org")
        #expect(store.load() == device)
    }

    @Test func aFailedClaimSavesNothing() async {
        let store = MemoryDeviceStore()
        await #expect(throws: ServerError.wrongCode) {
            try await Connection.pair("https://sync.example.org/koppeln#ABCD-EFGH", name: "x", store: store, transport: FakeTransport(.init(status: 403)))
        }
        #expect(store.load() == nil)
    }

    @Test func noCodeOrNoServerIsSaidBeforeAsking() async {
        let fake = FakeTransport()
        await #expect(throws: Connection.Problem.notACode) {
            try await Connection.pair("hello", name: "x", store: MemoryDeviceStore(), transport: fake)
        }
        await #expect(throws: Connection.Problem.needsServer) {
            try await Connection.pair("ABCD-EFGH", name: "x", store: MemoryDeviceStore(), transport: fake)
        }
        #expect(fake.requests.isEmpty)
    }

    @Test func signingOffForgetsTheDeviceEvenOffline() async {
        let device = Device(server: URL(string: "https://sync.example.org")!, token: "t", id: "d", name: "n", serverID: "s")
        let store = MemoryDeviceStore(device)
        let fake = FakeTransport()
        fake.failure = URLError(.notConnectedToInternet)
        await Connection.signOff(device, store: store, transport: fake)
        #expect(store.load() == nil)
        #expect(fake.requests.first?.httpMethod == "DELETE")
    }

    static let device = Device(server: URL(string: "https://sync.example.org")!, token: "t", id: "d", name: "n", serverID: "s")
    let cache = ReadModelCache(folder: FileManager.default.temporaryDirectory.appending(path: "connection-\(UUID().uuidString)"))
    let model = try! #require(ReadModelTests.models.first)

    @Test func refreshSavesANewerReadModel() async throws {
        let store = MemoryDeviceStore(Self.device)
        let fake = FakeTransport(.init(body: String(decoding: model, as: UTF8.self), headers: ["ETag": "\"x-1-2\""]))
        guard case .changed(let got) = await Connection.refresh(Self.device, store: store, cache: cache, transport: fake) else {
            Issue.record("expected a new read model")
            return
        }
        #expect(cache.load()?.model == got)
        #expect(await Connection.refresh(Self.device, store: store, cache: cache, transport: FakeTransport(.init(status: 304))) == .unchanged)
        cache.clear()
    }

    @Test func signedOffOnThePCForgetsTheDeviceAndItsDecks() async throws {
        let store = MemoryDeviceStore(Self.device)
        try cache.save(model, etag: "e")
        let fake = FakeTransport(.init(status: 401))
        #expect(await Connection.refresh(Self.device, store: store, cache: cache, transport: fake) == .signedOff)
        #expect(store.load() == nil)
        #expect(cache.load() == nil)
        #expect(fake.requests.first?.url?.path == "/api/app/data")
    }

    @Test func offlineOrAServerErrorKeepsTheDeviceAndItsDecks() async throws {
        let store = MemoryDeviceStore(Self.device)
        try cache.save(model, etag: "e")
        let offline = FakeTransport()
        offline.failure = URLError(.notConnectedToInternet)
        #expect(await Connection.refresh(Self.device, store: store, cache: cache, transport: offline) == .failed(ServerError.offline.message))
        let broken = await Connection.refresh(Self.device, store: store, cache: cache, transport: FakeTransport(.init(body: "not json")))
        #expect(broken == .failed("Couldn't update. Please try again."))
        #expect(await Connection.refresh(Self.device, store: store, cache: cache, transport: FakeTransport(.init(status: 502))) != .signedOff)
        #expect(store.load() == Self.device)
        #expect(cache.load()?.etag == "e")
        cache.clear()
    }

    @Test func aSignOffOfAnOldDeviceKeepsTheNewOne() async throws {
        let new = Device(server: URL(string: "https://sync.example.org")!, token: "t2", id: "new", name: "n", serverID: "s")
        let store = MemoryDeviceStore(new)
        try cache.save(model, etag: "e")
        #expect(await Connection.refresh(Self.device, store: store, cache: cache, transport: FakeTransport(.init(status: 401))) == .signedOff)
        #expect(store.load() == new)
        #expect(cache.load() != nil)
        cache.clear()
    }

    @Test func everyProblemHasAMessage() {
        #expect(Connection.Problem.notACode.message.contains("Pair a device"))
        #expect(Connection.Problem.needsServer.message.contains("address"))
        let errors: [ServerError] = [.wrongCode, .tooManyTries, .signedOff, .offline, .failed(status: 502, message: "")]
        #expect(Set(errors.map(\.message)).count == errors.count)
        #expect(ServerError.failed(status: 502, message: "").message.contains("502"))
        #expect(ServerError.failed(status: 503, message: "Gerade beschäftigt").message == "Gerade beschäftigt")
        #expect(Connection.message(for: ServerError.wrongCode) == ServerError.wrongCode.message)
        #expect(Connection.message(for: Connection.Problem.needsServer) == Connection.Problem.needsServer.message)
        #expect(Connection.message(for: URLError(.badURL)).contains("try again"))
    }
}
