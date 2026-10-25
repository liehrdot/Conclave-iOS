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

    @Test func signedOffOnThePCForgetsTheDevice() async {
        let device = Device(server: URL(string: "https://sync.example.org")!, token: "t", id: "d", name: "n", serverID: "s")
        let store = MemoryDeviceStore(device)
        let fake = FakeTransport(.init(status: 401))
        #expect(await Connection.stillPaired(device, store: store, transport: fake) == false)
        #expect(store.load() == nil)
        #expect(fake.requests.first?.url?.path == "/api/app/status")
    }

    @Test func offlineOrAServerErrorKeepsTheDevice() async {
        let device = Device(server: URL(string: "https://sync.example.org")!, token: "t", id: "d", name: "n", serverID: "s")
        let store = MemoryDeviceStore(device)
        let offline = FakeTransport()
        offline.failure = URLError(.notConnectedToInternet)
        #expect(await Connection.stillPaired(device, store: store, transport: offline))
        #expect(await Connection.stillPaired(device, store: store, transport: FakeTransport(.init(status: 502))))
        #expect(await Connection.stillPaired(device, store: store, transport: FakeTransport(.init(body: #"{"etag": "x", "pcs": []}"#))))
        #expect(store.load() == device)
    }

    @Test func aSignOffOfAnOldDeviceKeepsTheNewOne() async throws {
        let old = Device(server: URL(string: "https://sync.example.org")!, token: "t", id: "old", name: "n", serverID: "s")
        let new = Device(server: URL(string: "https://sync.example.org")!, token: "t2", id: "new", name: "n", serverID: "s")
        let store = MemoryDeviceStore(new)
        #expect(await Connection.stillPaired(old, store: store, transport: FakeTransport(.init(status: 401))) == false)
        #expect(store.load() == new)
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
