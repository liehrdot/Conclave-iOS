import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import ConclaveCore

@Suite struct PrintingTests {
    /// Sol Ring from Commander 2021, as Scryfall sends it (only the keys that matter).
    static let solRing = #"""
    {"object": "card", "id": "4cbc6901-6a4a-4d0a-83ea-7eefa3b35021", "oracle_id": "6ad8011d-3471-4369-9d68-b264cc027487",
     "name": "Sol Ring", "lang": "en", "set": "c21", "set_name": "Commander 2021", "collector_number": "263",
     "released_at": "2021-04-23", "finishes": ["nonfoil"], "image_uris": {"normal": "https://cards.scryfall.io/normal/front/4/c/4cbc.jpg"},
     "prices": {"eur": "1.20", "eur_foil": null, "usd": "1.50", "usd_foil": null}}
    """#
    static let germanSolRing = #"""
    {"object": "card", "id": "aaaaaaaa-6a4a-4d0a-83ea-7eefa3b35021", "oracle_id": "6ad8011d-3471-4369-9d68-b264cc027487",
     "name": "Sol Ring", "printed_name": "Sol-Ring", "lang": "de", "set": "c21", "set_name": "Commander 2021",
     "collector_number": "263", "finishes": ["nonfoil", "foil"], "prices": {"eur": null, "eur_foil": "4.00"}}
    """#
    static let fable = #"""
    {"object": "card", "id": "bbbbbbbb-6a4a-4d0a-83ea-7eefa3b35021", "name": "Fable of the Mirror-Breaker // Reflection of Kiki-Jiki",
     "lang": "en", "set": "neo", "set_name": "Kamigawa: Neon Dynasty", "collector_number": "141", "finishes": ["foil"],
     "card_faces": [{"image_uris": {"normal": "https://cards.scryfall.io/normal/front/b/b/bbbb.jpg"}},
                    {"image_uris": {"normal": "https://cards.scryfall.io/normal/back/b/b/bbbb.jpg"}}]}
    """#

    static func make(_ answers: FakeTransport.Answer...) -> (Scryfall, FakeTransport) {
        let fake = FakeTransport(answers: answers)
        return (Scryfall(transport: fake, gap: .zero), fake)
    }

    @Test func aPrintingBySetAndNumberInALanguage() async throws {
        let (scryfall, fake) = Self.make(.init(body: Self.germanSolRing), .init(status: 404))
        let german = try #require(try await scryfall.printing(set: "C21", number: "263", lang: "de"))
        #expect(fake.requests[0].url?.path == "/cards/c21/263/de")
        #expect(german.shownName == "Sol-Ring" && german.lang == "de")
        #expect(try await scryfall.printing(set: "c21", number: "999") == nil)  // 404: no such printing
        #expect(fake.requests[1].url?.path == "/cards/c21/999")
    }

    @Test func aFuzzyNameInOneSet() async throws {
        let (scryfall, fake) = Self.make(.init(body: Self.solRing))
        let sol = try #require(try await scryfall.printing(named: "Sol Rinq", set: "C21"))
        #expect(sol.id == "4cbc6901-6a4a-4d0a-83ea-7eefa3b35021" && sol.collectorNumber == "263" && sol.released == "2021-04-23")
        let items = URLComponents(url: try #require(fake.requests.first?.url), resolvingAgainstBaseURL: false)?.queryItems
        #expect(items == [URLQueryItem(name: "fuzzy", value: "Sol Rinq"), URLQueryItem(name: "set", value: "c21")])
    }

    @Test func allPrintingsPageByPage() async throws {
        let page1 = #"{"object": "list", "has_more": true, "data": [\#(Self.solRing)]}"#
        let page2 = #"{"object": "list", "has_more": false, "data": [\#(Self.germanSolRing)]}"#
        let (scryfall, fake) = Self.make(.init(body: page1), .init(body: page2))
        let all = try await scryfall.printings(of: "6ad8", anyLanguage: true)
        #expect(all.map(\.lang) == ["en", "de"])
        let query = URLComponents(url: try #require(fake.requests.first?.url), resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(query.first { $0.name == "q" }?.value == "oracleid:6ad8 game:paper")
        #expect(query.contains(URLQueryItem(name: "include_multilingual", value: "true")))
        let (english, fake2) = Self.make(.init(status: 404))
        #expect(try await english.printings(of: "6ad8").isEmpty)
        let q2 = URLComponents(url: try #require(fake2.requests.first?.url), resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(q2.first { $0.name == "q" }?.value == "oracleid:6ad8 lang:en game:paper")
    }

    @Test func aDoubleFacedCardHasABack() throws {
        let fable = try #require(try Scryfall.decoder.decode(ScryfallCard.self, from: Data(Self.fable.utf8)).printing)
        #expect(fable.image?.absoluteString.contains("/front/") == true)
        #expect(fable.imageBack?.absoluteString.contains("/back/") == true)
        #expect(!fable.hasNonfoil && fable.hasFoil)
    }

    static func printing(_ json: String) -> Printing {
        try! Scryfall.decoder.decode(ScryfallCard.self, from: Data(json.utf8)).printing!
    }

    @Test func theDraftFollowsThePrintingsFinishes() {
        var draft = CollectionAddDraft(Self.printing(Self.solRing))
        #expect(!draft.foil)
        draft.setFoil(true)
        #expect(!draft.foil)  // this Sol Ring was never made as a foil
        draft.pick(Self.printing(Self.germanSolRing))
        draft.setFoil(true)
        #expect(draft.foil && draft.lang == "de")
        draft.pick(Self.printing(Self.fable))
        #expect(draft.foil)  // only made as a foil
        #expect(CollectionAddDraft(Self.printing(Self.fable)).foil)
        draft.copies = 500
        #expect(draft.copies == 99)
        draft.copies = 0
        #expect(draft.copies == 1)
    }

    @Test func theAddIsWhatThePWASends() throws {
        var draft = CollectionAddDraft(Self.printing(Self.germanSolRing), proxy: true)
        draft.setFoil(true)
        draft.copies = 2
        draft.place = "Binder"
        let entry = try #require(draft.payload(id: "n1")["entry"]?.object)
        #expect(entry["id"] == .string("n1") && entry["name"] == .string("Sol Ring") && entry["qty"] == .int(2))
        #expect(entry["scryfall_id"] == .string("aaaaaaaa-6a4a-4d0a-83ea-7eefa3b35021") && entry["lang"] == .string("de"))
        #expect(entry["price_eur"] == .string("4.00"))  // the foil price
        #expect(entry["proxy"] == .bool(true) && entry["foil"] == .bool(true))
        #expect(entry["place"] == .string("Binder") && entry["place_deck"] == .string(""))
        draft.deck = "meren"
        #expect(draft.payload()["entry"]?["place"] == .string(""))  // a deck wins over the text
    }

    @Test func anAddShowsAtOnceAndUndoTakesItBack() throws {
        let base = try #require(APICasesTests.file["bases"]?["default"])
        var draft = CollectionAddDraft(Self.printing(Self.solRing))
        draft.place = "binder"
        let add = PendingOp(type: "collection.add", payload: draft.payload())
        let more = try ReadModel.decode(Optimistic.apply([add], to: base))
        #expect(more.collection.first { $0.id == "c1" }?.qty == 3)  // the same printing and place: one more copy
        let (type, back) = try #require(Outbox.inverse(add.type, add.payload))
        let undone = try ReadModel.decode(Optimistic.apply([add, PendingOp(type: type, payload: back)], to: base))
        #expect(undone.collection == (try ReadModel.decode(base)).collection)
        #expect(add.summary(in: more) == "Sol Ring")
    }
}
