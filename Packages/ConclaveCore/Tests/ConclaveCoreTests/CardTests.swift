import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import ConclaveCore

/// Scryfall's answers, cut down to the keys the app reads.
enum Scry {
    static let sol = #"{"name": "Sol Ring", "lang": "en", "mana_cost": "{1}", "type_line": "Artifact", "oracle_text": "{T}: Add {C}{C}.", "color_identity": [], "image_uris": {"normal": "https://cards.scryfall.io/normal/front/a/b/sol.jpg", "art_crop": "https://cards.scryfall.io/art_crop/front/a/b/sol.jpg"}, "scryfall_uri": "https://scryfall.com/card/c21/263/sol-ring"}"#
    static let fable = #"{"name": "Fable of the Mirror-Breaker // Reflection of Kiki-Jiki", "lang": "en", "color_identity": ["R"], "card_faces": [{"name": "Fable of the Mirror-Breaker", "mana_cost": "{2}{R}", "type_line": "Enchantment — Saga", "oracle_text": "(As this Saga enters…)", "image_uris": {"normal": "https://cards.scryfall.io/normal/front/f/a/fable.jpg", "art_crop": "https://cards.scryfall.io/art_crop/front/f/a/fable.jpg"}}, {"name": "Reflection of Kiki-Jiki", "mana_cost": "", "type_line": "Enchantment Creature — Goblin Shaman", "oracle_text": "{1}, {T}: Create a token…", "power": "2", "toughness": "2", "image_uris": {"normal": "https://cards.scryfall.io/normal/back/f/a/fable.jpg"}}]}"#
    static let bonecrusher = #"{"name": "Bonecrusher Giant // Stomp", "color_identity": ["R"], "image_uris": {"normal": "https://cards.scryfall.io/normal/front/b/c/bone.jpg"}, "card_faces": [{"name": "Bonecrusher Giant", "mana_cost": "{2}{R}", "type_line": "Creature — Giant", "oracle_text": "Whenever…", "power": "4", "toughness": "3"}, {"name": "Stomp", "mana_cost": "{1}{R}", "type_line": "Instant — Adventure", "oracle_text": "Damage can't be prevented this turn."}]}"#
    static func collection(_ cards: String...) -> String { #"{"object": "list", "not_found": [], "data": ["# + cards.joined(separator: ",") + "]}" }
}

@Suite struct CardTests {
    @Test func aNormalCardHasOneFace() async throws {
        let fake = FakeTransport(.init(body: Scry.collection(Scry.sol)))
        let found = try await Scryfall(transport: fake, gap: .zero).cards(named: ["Sol Ring", "Nope"])
        let sol = try #require(found["Sol Ring"])
        #expect(found["Nope"] == nil)
        #expect(sol.faces.count == 1)
        #expect(sol.faces[0].text == "{T}: Add {C}{C}.")
        #expect(sol.faces[0].manaCost == "{1}")
        #expect(sol.image?.lastPathComponent == "sol.jpg")
        #expect(sol.back == nil)
        #expect(sol.colors == "")

        let request = try #require(fake.requests.first)
        #expect(request.url?.absoluteString == "https://api.scryfall.com/cards/collection")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(request.value(forHTTPHeaderField: "User-Agent")?.hasPrefix("Conclave") == true)
    }

    @Test func aDoubleFacedCardIsAskedByItsFrontAndHasABack() async throws {
        let fake = FakeTransport(.init(body: Scry.collection(Scry.fable)))
        let name = "Fable of the Mirror-Breaker // Reflection of Kiki-Jiki"
        let found = try await Scryfall(transport: fake, gap: .zero).cards(named: [name])
        let body = try JSONDecoder().decode([String: [[String: String]]].self, from: try #require(fake.requests.first?.httpBody))
        #expect(body == ["identifiers": [["name": "Fable of the Mirror-Breaker"]]])
        let fable = try #require(found[name])
        #expect(fable.faces.map(\.name) == ["Fable of the Mirror-Breaker", "Reflection of Kiki-Jiki"])
        #expect(fable.faces[1].stats == "2/2")
        #expect(fable.image?.absoluteString == "https://cards.scryfall.io/normal/front/f/a/fable.jpg")
        #expect(fable.back?.absoluteString == "https://cards.scryfall.io/normal/back/f/a/fable.jpg")
        #expect(fable.front == "Fable of the Mirror-Breaker")
    }

    @Test func anAdventureHasTwoFacesButOnePicture() async throws {
        let fake = FakeTransport(.init(body: Scry.collection(Scry.bonecrusher)))
        let found = try await Scryfall(transport: fake, gap: .zero).cards(named: ["Bonecrusher Giant"])
        let giant = try #require(found["Bonecrusher Giant"])  // asked by the front face only
        #expect(giant.faces.count == 2)
        #expect(giant.image?.lastPathComponent == "bone.jpg")
        #expect(giant.back == nil)
    }

    @Test func manyNamesGoInBatchesOf75() async throws {
        let fake = FakeTransport(.init(body: Scry.collection()), .init(body: Scry.collection(Scry.sol)))
        let names = (1...75).map { "Filler \($0)" } + ["Sol Ring"]
        let found = try await Scryfall(transport: fake, gap: .zero).cards(named: names)
        #expect(fake.requests.count == 2)
        #expect(found.keys.sorted() == ["Sol Ring"])
    }

    @Test func errors() async {
        await #expect(throws: CardError.failed(status: 503)) {
            try await Scryfall(transport: FakeTransport(.init(status: 503)), gap: .zero).cards(named: ["Sol Ring"])
        }
        let offline = FakeTransport()
        offline.failure = URLError(.notConnectedToInternet)
        await #expect(throws: CardError.offline) {
            try await Scryfall(transport: offline, gap: .zero).cards(named: ["Sol Ring"])
        }
    }

    @Test func requestsWaitTheirTurn() async throws {
        let fake = FakeTransport(.init(body: Scry.collection()), .init(body: Scry.collection()))
        let scryfall = Scryfall(transport: fake, gap: .milliseconds(150))
        let clock = ContinuousClock()
        let took = try await clock.measure {
            async let a = scryfall.cards(named: ["A"])
            async let b = scryfall.cards(named: ["B"])
            _ = try await (a, b)
        }
        #expect(took >= .milliseconds(150))
    }
}

@Suite struct CardLibraryTests {
    func folder() -> URL { FileManager.default.temporaryDirectory.appending(path: "cards-\(UUID().uuidString)") }

    @Test func aCardLookedUpOnceShowsAgainOffline() async throws {
        let file = folder().appending(path: "cards.json")
        let fake = FakeTransport(.init(body: Scry.collection(Scry.fable)))
        let library = CardLibrary(scryfall: Scryfall(transport: fake, gap: .zero), file: file)
        let name = "Fable of the Mirror-Breaker // Reflection of Kiki-Jiki"
        #expect(try await library.card(named: name)?.name == name)

        let offline = FakeTransport()
        offline.failure = URLError(.notConnectedToInternet)
        let later = CardLibrary(scryfall: Scryfall(transport: offline, gap: .zero), file: file)
        #expect(try await later.card(named: name)?.faces.count == 2)
        #expect(await later.cached("Fable of the Mirror-Breaker")?.name == name)  // the front face finds it too
        #expect(offline.requests.isEmpty)
        await #expect(throws: CardError.offline) { try await later.card(named: "Sol Ring") }
    }

    @Test func prefetchAsksOnlyForTheMissingOnesAndUnknownNamesOnce() async throws {
        let fake = FakeTransport(.init(body: Scry.collection(Scry.sol)), .init(body: Scry.collection(Scry.bonecrusher)))
        let library = CardLibrary(scryfall: Scryfall(transport: fake, gap: .zero), file: nil)
        await library.prefetch(["Sol Ring", "Sol Ring", "Made Up"])
        await library.prefetch(["Sol Ring", "Made Up", "Bonecrusher Giant"])
        #expect(fake.requests.count == 2)
        let second = try JSONDecoder().decode([String: [[String: String]]].self, from: try #require(fake.requests.last?.httpBody))
        #expect(second == ["identifiers": [["name": "Bonecrusher Giant"]]])
        #expect(try await library.card(named: "Made Up") == nil)
        #expect(fake.requests.count == 2)
    }

    @Test func clearForgetsTheFile() async throws {
        let file = folder().appending(path: "cards.json")
        let library = CardLibrary(scryfall: Scryfall(transport: FakeTransport(.init(body: Scry.collection(Scry.sol))), gap: .zero), file: file)
        _ = try await library.card(named: "Sol Ring")
        #expect(FileManager.default.fileExists(atPath: file.path))
        await library.clear()
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(await library.cached("Sol Ring") == nil)
    }
}

@Suite struct ManaTests {
    @Test func symbolsAndText() {
        #expect(Mana.pieces("{T}: Add {G}.") == [.symbol(.init("T")), .text(": Add "), .symbol(.init("G")), .text(".")])
        #expect(Mana.pieces("no symbols") == [.text("no symbols")])
        #expect(Mana.pieces("{ broken") == [.text("{ broken")])
        #expect(Mana.pieces("{}{2}") == [.text("{}"), .symbol(.init("2"))])
    }

    @Test func kinds() {
        #expect(Mana.Symbol("B").kind == .color("B"))
        #expect(Mana.Symbol("C").kind == .color("C"))
        #expect(Mana.Symbol("10").kind == .generic("10"))
        #expect(Mana.Symbol("X").kind == .generic("X"))
        #expect(Mana.Symbol("B/R").kind == .hybrid("B", "R"))
        #expect(Mana.Symbol("2/W").kind == .hybrid("2", "W"))
        #expect(Mana.Symbol("G/P").kind == .phyrexian("G"))
        #expect(Mana.Symbol("G/U/P").kind == .phyrexian("G"))
        #expect(Mana.Symbol("T").kind == .glyph("T"))
    }

    @Test func voiceOverReadsTheNames() {
        #expect(Mana.spoken("{2}{B}{G}") == "2, black, green")
        #expect(Mana.spoken("{T}: Add {C}{C}.") == "tap: Add colorlesscolorless.")
        #expect(Mana.Symbol("2/W").spoken == "2 or white")
        #expect(Mana.Symbol("R/P").spoken == "Phyrexian red")
    }
}

@Suite struct DeckCopiesTests {
    /// A deck from the shared cases with made-up cards.
    var deck: Deck {
        get throws {
            let model = try ReadModel.decode(try #require(ReadModelTests.models.first))
            var deck = try #require(model.decks.first)
            deck.slug = "meren"
            deck.cards = [.init(name: "Birds of Paradise", qty: 1), .init(name: "Forest", qty: 3),
                          .init(name: "Fable of the Mirror-Breaker // Reflection of Kiki-Jiki", qty: 1)]
            return deck
        }
    }

    @Test func theReadModelHasTheCollection() throws {
        let models = try ReadModelTests.models.map(ReadModel.decode)
        let entry = try #require(models.flatMap(\.collection).first)
        #expect(!entry.name.isEmpty)
        #expect(entry.qty > 0)
    }

    @Test func copiesInTheDeckRealAndFoilFirstCappedAtTheDecksCount() throws {
        let deck = try deck
        let model = ReadModel(collection: [
            .init(id: "1", name: "Forest", qty: 2, proxy: true, placeDeck: "meren"),
            .init(id: "2", name: "Forest", qty: 1, placeDeck: "meren"),
            .init(id: "3", name: "Forest", qty: 1, foil: true, placeDeck: "meren"),
            .init(id: "4", name: "Forest", qty: 5, place: "Bulk"),
            .init(id: "5", name: "Birds of Paradise", qty: 1, placeDeck: "other"),
            .init(id: "6", name: "Fable of the Mirror-Breaker", qty: 1, placeDeck: "meren"),
        ])
        let forests = model.copies(of: "Forest", in: deck)
        #expect(forests.map(\.id) == ["3", "2", "1"])
        #expect(forests.map(\.qty) == [1, 1, 1])  // the proxy entry has 2, the deck needs only one more
        #expect(model.copies(of: "Birds of Paradise", in: deck).isEmpty)  // it lies in another deck
        #expect(model.copies(of: "Fable of the Mirror-Breaker // Reflection of Kiki-Jiki", in: deck).map(\.id) == ["6"])
    }

    @Test func imageFromTheScryfallId() {
        let entry = CollectionEntry(id: "1", name: "Birds of Paradise", set: "msc", setName: "Marvel Super Heroes Commander",
                                    collectorNumber: "170", scryfallId: "492c2f9a-51e7-4e0f-9899-23bf43ea988b")
        #expect(entry.imageURL()?.absoluteString == "https://cards.scryfall.io/normal/front/4/9/492c2f9a-51e7-4e0f-9899-23bf43ea988b.jpg")
        #expect(entry.imageURL(.small, back: true)?.absoluteString == "https://cards.scryfall.io/small/back/4/9/492c2f9a-51e7-4e0f-9899-23bf43ea988b.jpg")
        #expect(entry.printing == "Marvel Super Heroes Commander · #170")
        let typed = CollectionEntry(id: "2", name: "X", scryfallId: "not-an-id", image: URL(string: "https://cards.scryfall.io/x.jpg"))
        #expect(typed.imageURL()?.absoluteString == "https://cards.scryfall.io/x.jpg")
        #expect(typed.imageURL(back: true) == nil)
    }
}
