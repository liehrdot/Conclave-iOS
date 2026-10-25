import Foundation
import Testing
@testable import ConclaveCore

@Suite struct PairingTests {
    @Test func linkCarriesTheServer() {
        let got = Pairing.parse("https://Sync.Example.org/koppeln#abcd-efgh")
        #expect(got == Pairing(server: URL(string: "https://sync.example.org")!, code: "ABCD-EFGH"))
    }

    @Test func appLinkAndPortWork() {
        let got = Pairing.parse("https://sync.example.org:8443/app/#ABCDEFGH")
        #expect(got?.server.absoluteString == "https://sync.example.org:8443")
        #expect(got?.code == "ABCD-EFGH")
    }

    @Test func bareCodeNeedsAServer() {
        #expect(Pairing.parse("ABCD-EFGH") == nil)
        let got = Pairing.parse(" abcd-efgh ", server: "conclave-cloud.duckdns.org")
        #expect(got?.server.absoluteString == "https://conclave-cloud.duckdns.org")
    }

    @Test func refusesWhatIsNoCode() {
        #expect(Pairing.parse("hello", server: "sync.example.org") == nil)
        #expect(Pairing.parse("ABCD-EFG1", server: "sync.example.org") == nil)  // 1 is never in a code
        #expect(Pairing.parse("https://sync.example.org/koppeln", server: "other.example.org") == nil)
    }

    @Test func normalizesServers() {
        #expect(Pairing.normalizeServer("sync.example.org/app/")?.absoluteString == "https://sync.example.org")
        #expect(Pairing.normalizeServer("http://localhost:8080")?.absoluteString == "http://localhost:8080")
        #expect(Pairing.normalizeServer("nonsense") == nil)
        #expect(Pairing.normalizeServer("ftp://sync.example.org") == nil)
        #expect(Pairing.normalizeServer("") == nil)
    }
}
