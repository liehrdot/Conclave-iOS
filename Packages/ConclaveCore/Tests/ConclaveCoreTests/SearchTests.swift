import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import ConclaveCore

@Suite struct SearchTests {
    static let german = #"{"name": "Llanowar Elves", "lang": "de", "printed_name": "Elfen von Llanowar", "type_line": "Creature — Elf Druid", "color_identity": ["G"]}"#
    static let growth = #"{"name": "Rampant Growth", "lang": "en", "type_line": "Sorcery", "color_identity": ["G"]}"#
    static let studious = #"{"name": "Studious First-Year // Rampant Growth", "lang": "en", "color_identity": ["G"], "card_faces": [{"name": "Studious First-Year", "type_line": "Creature — Bear Wizard"}, {"name": "Rampant Growth", "type_line": "Sorcery"}]}"#
    static func page(_ cards: String..., total: Int? = nil, more: Bool = false) -> String {
        #"{"object": "list", "total_cards": \#(total ?? cards.count), "has_more": \#(more), "data": ["# + cards.joined(separator: ",") + "]}"
    }

    func query(_ request: URLRequest?) -> [String: String] {
        let items = URLComponents(url: request!.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    }

    @Test func aQueryGivesOnePageMostPlayedFirst() async throws {
        let fake = FakeTransport(.init(body: Self.page(Scry.sol, total: 300, more: true)))
        let page = try await Scryfall(transport: fake, gap: .zero).search("o:+1/+1 id<=g", page: 2)
        #expect(page.cards.map(\.name) == ["Sol Ring"])
        #expect(page.total == 300)
        #expect(page.next == 3)
        let request = try #require(fake.requests.first)
        #expect(request.url?.path == "/cards/search")
        #expect(query(request) == ["q": "o:+1/+1 id<=g", "unique": "cards", "order": "edhrec", "page": "2"])
        // a "+" left as is would reach Scryfall as a space
        #expect(request.url?.absoluteString.contains("%2B1/%2B1") == true)
    }

    @Test func aFoundCardIsAHitWithItsFacesTypes() async throws {
        let fake = FakeTransport(.init(body: Self.page(Self.studious)))
        let hit = NameHit(try #require(try await Scryfall(transport: fake, gap: .zero).search("t:bear").cards.first))
        #expect(hit.name == "Studious First-Year // Rampant Growth")
        #expect(hit.type == "Creature — Bear Wizard // Sorcery")
        #expect(hit.german == nil && hit.card != nil)
    }

    @Test func noHitsIsAnEmptyPageAndABrokenQueryAnError() async throws {
        let none = try await Scryfall(transport: FakeTransport(.init(status: 404)), gap: .zero).search("t:nothing")
        #expect(none == SearchPage(cards: [], total: 0, next: nil))
        await #expect(throws: CardError.badQuery("")) {
            try await Scryfall(transport: FakeTransport(.init(status: 400)), gap: .zero).search("((")
        }
    }

    @Test func aNameFindsGermanAndEnglishCardsAndTheAutocompletesNames() async throws {
        let fake = FakeTransport(.init(body: Self.page(Self.german, Scry.sol)),
                                 .init(body: #"{"data": ["Sol Ring", "Sol Talisman"]}"#))
        let hits = try await Scryfall(transport: fake, gap: .zero).find(name: " sol ")
        #expect(hits.map(\.name) == ["Llanowar Elves", "Sol Ring", "Sol Talisman"])
        #expect(hits[0].german == "Elfen von Llanowar")
        #expect(hits[0].card == nil)  // a German printing: the sheet looks the English card up
        #expect(hits[1].card?.name == "Sol Ring")
        #expect(hits[2].type == "")
        #expect(query(fake.requests[0])["include_multilingual"] == "true")
        #expect(fake.requests[1].url?.path == "/cards/autocomplete")
    }

    @Test func theExactNameComesFirst() async throws {
        let fake = FakeTransport(.init(body: Self.page(Self.studious, Self.growth)), .init(body: #"{"data": []}"#))
        let hits = try await Scryfall(transport: fake, gap: .zero).find(name: "rampant growth")
        #expect(hits.map(\.name) == ["Rampant Growth", "Studious First-Year // Rampant Growth"])
        let german = NameHit(name: "Llanowar Elves", german: "Elfen von Llanowar", type: "", card: nil)
        let other = NameHit(name: "Elvish Mystic", german: nil, type: "", card: nil)
        #expect(NameHit.exactFirst([other, german], "elfen von llanowar").map(\.name) == ["Llanowar Elves", "Elvish Mystic"])
    }

    @Test func aNameWithoutHitsIsEmptyAndOfflineThrows() async throws {
        let none = FakeTransport(.init(status: 404), .init(body: #"{"data": []}"#))
        #expect(try await Scryfall(transport: none, gap: .zero).find(name: "xyzzy").isEmpty)
        #expect(try await Scryfall(transport: FakeTransport(), gap: .zero).find(name: "  ").isEmpty)
        let offline = FakeTransport()
        offline.failure = URLError(.notConnectedToInternet)
        await #expect(throws: CardError.offline) {
            try await Scryfall(transport: offline, gap: .zero).find(name: "sol")
        }
    }

    @Test func theLibraryKeepsOnlyEnglishCardsFromASearch() async throws {
        let library = CardLibrary(scryfall: Scryfall(transport: FakeTransport(), gap: .zero), file: nil)
        let english = try Scryfall.decoder.decode(ScryfallCard.self, from: Data(Scry.fable.utf8)).card
        let german = try Scryfall.decoder.decode(ScryfallCard.self, from: Data(Self.german.utf8)).card
        await library.remember([english, german])
        #expect(await library.cached("Fable of the Mirror-Breaker")?.name == english.name)
        #expect(await library.cached("Llanowar Elves") == nil)
    }
}
