import Foundation
import Testing
@testable import ConclaveCore

@Suite struct ReadModelTests {
    /// Every read model in the shared cases, as JSON: the bases and every changed key of every case.
    static var models: [Data] {
        let bases = APICasesTests.file["bases"]?.object ?? [:]
        let afters = APICasesTests.cases.compactMap { item -> JSONValue? in
            guard let after = item["after"]?.object, let base = item["base"]?.string, case .object(var model)? = bases[base]
            else { return nil }
            model.merge(after) { $1 }
            return .object(model)
        }
        return (Array(bases.values) + afters).map { try! JSONEncoder().encode($0) }
    }

    @Test func decodesEveryReadModelTheServerWrites() throws {
        #expect(Self.models.count > 20)
        for data in Self.models {
            let model = try ReadModel.decode(data)
            #expect(!model.decks.isEmpty)
        }
    }

    @Test func readsADeck() throws {
        let model = try ReadModel.decode(try #require(Self.models.first))
        let kaalia = try #require(model.decks.first { $0.slug == "kaalia" })
        #expect(kaalia.name == "Kaalia")
        #expect(kaalia.commanders == ["Kaalia of the Vast"])
        #expect(kaalia.colors == "RWB")
        #expect(kaalia.bracket == 2)
        #expect(kaalia.rule0.rows.first?.value == "Bracket 2 (Core)")
        #expect(kaalia.rule0.text.contains("Rule 0"))
        #expect(kaalia.shownRule0.rows.first?.label == "Level")
        #expect(kaalia.shownRule0.text.hasSuffix("Does this fit your table?"))
        #expect(kaalia.shownRule0.rows.map(\.flag) == kaalia.rule0.rows.map(\.flag))
        #expect(kaalia.shownLevel == "Bracket 2")
        #expect(kaalia.cardCount == kaalia.cards.reduce(0) { $0 + ($1.qty ?? 1) })
    }

    @Test func readsOpponentsAndGames() throws {
        let models = try Self.models.map(ReadModel.decode)
        let model = try #require(models.first { !$0.games.isEmpty && !$0.opponents.isEmpty })
        let opponent = try #require(model.opponents.first { !$0.notes.isEmpty })
        #expect(!opponent.title.isEmpty)
        #expect(opponent.record.games >= 0)
        let game = try #require(model.games.first)
        let deck = try #require(model.decks.first { $0.slug == game.deck })
        #expect(model.games(of: deck).contains(game))
        #expect(["win", "loss", "draw"].contains(game.result))
    }

    @Test func showsTheEnglishOptions() throws {
        let model = try ReadModel.decode(try #require(Self.models.first))
        #expect(model.shownOptions.results["win"] == "Win")
        #expect(model.options.results["win"] == "Sieg")
        #expect(model.shownOptions.tags.map(\.key) == model.options.tags.map(\.key))
        #expect(Options.label("combat", in: model.shownOptions.how) == "combat damage")
        #expect(Options.label("unknown", in: model.shownOptions.how) == "unknown")
    }

    @Test func anOlderServerFallsBackToGerman() throws {
        let json = #"""
        {"decks": [{"slug": "a", "name": "A", "commanders": [], "colors": "", "proxy": false, "checking": false,
          "level": "oberes Bracket 3", "rule0": {"rows": [{"label": "Stufe", "value": "x", "flag": false}], "text": "t"},
          "speed": {"label": "Schnell", "text": "s"}, "cards": [], "maybe": [], "record": {"games": 0, "wins": 0, "losses": 0, "draws": 0},
          "pinned": false, "shelved": false}],
         "options": {"results": {"win": "Sieg"}, "issues": [["slow", "zu langsam"], ["bad"]], "tags": [], "how": []}}
        """#
        let model = try ReadModel.decode(Data(json.utf8))
        let deck = try #require(model.decks.first)
        #expect(deck.shownRule0.rows.first?.label == "Stufe")
        #expect(deck.shownLevel == "oberes Bracket 3")
        #expect(deck.speed?.shownLabel == "Schnell" && deck.speed?.shownText == "s")
        #expect(model.shownOptions.results["win"] == "Sieg")
        #expect(model.shownOptions.issues == [Options.Choice(key: "slow", label: "zu langsam")])
    }

    @Test func missingListsAndUnknownKeysAreFine() throws {
        let model = try ReadModel.decode(Data(#"{"version": 2, "something_new": {"a": 1}}"#.utf8))
        #expect(model == ReadModel())
    }

    @Test func readsTheServersTimes() {
        let plain = ReadModel.date("2026-10-02T20:00:00+00:00")
        let zulu = ReadModel.date("2026-10-02T20:00:00Z")
        let fraction = ReadModel.date("2026-10-02T20:00:00.250Z")
        #expect(plain != nil && plain == zulu)
        #expect(fraction.map { $0.timeIntervalSince(zulu!) } == 0.25)
        #expect(ReadModel.date(nil) == nil)
        #expect(ReadModel.date("") == nil)
        #expect(ReadModel.date("yesterday") == nil)
    }
}
