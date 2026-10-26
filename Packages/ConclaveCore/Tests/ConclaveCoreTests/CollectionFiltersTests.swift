import Foundation
import Testing
@testable import ConclaveCore

@Suite struct CollectionFiltersTests {
    static func card(_ name: String, colors: String, type: String) -> Card {
        Card(name: name, faces: [.init(name: name, manaCost: "", typeLine: type, text: "", stats: nil, image: nil)],
             colors: colors, image: nil, art: nil, link: nil, lang: "en")
    }

    static let cards = [
        "Sol Ring": card("Sol Ring", colors: "", type: "Artifact"),
        "Forest": card("Forest", colors: "", type: "Basic Land — Forest"),
        "Llanowar Elves": card("Llanowar Elves", colors: "G", type: "Creature — Elf Druid"),
        "Putrefy": card("Putrefy", colors: "BG", type: "Instant"),
    ]

    /// The merge base (2 Sol Rings in the Binder, 1 in the Kiste, 10 Forests in Meren) plus elves and Putrefy.
    static var library: ReadModel {
        var library = try! ReadModel.decode(APICasesTests.file["bases"]!["collection-update-merge"]!)
        library.collection += [
            CollectionEntry(id: "e1", name: "Llanowar Elves", qty: 4, lang: "de", set: "fdn", setName: "Foundations", priceEur: "0.20"),
            CollectionEntry(id: "p1", name: "Putrefy", qty: 1, proxy: true, set: "dis", setName: "Dissension", priceEur: "9.00", place: "binder"),
            CollectionEntry(id: "p2", name: "Putrefy", qty: 1, set: "gpt", setName: "Guildpact", priceEur: "6.00"),
        ]
        return library
    }

    func names(_ filters: CollectionFilters, sort: CollectionSort = .name) -> [String] {
        Self.library.collectionGroups(filters: filters, sort: sort) { Self.cards[$0] }.map(\.name)
    }

    @Test func noFiltersKeepsTheList() {
        #expect(names(CollectionFilters()) == Self.library.collectionGroups().map(\.name))
    }

    @Test func colorsWorkLikeAColorIdentity() {
        var filters = CollectionFilters()
        filters.colors = ["G"]
        #expect(names(filters) == ["Llanowar Elves"])
        filters.colors = ["B", "G"]
        #expect(names(filters) == ["Llanowar Elves", "Putrefy"])
        filters.colors = ["C"]
        #expect(names(filters) == ["Forest", "Sol Ring"])
        // without the card's data, a colour filter can't tell: the card waits
        #expect(Self.library.collectionGroups(filters: filters) { _ in nil }.isEmpty)
    }

    @Test func typesLookAtTheTypeLine() {
        var filters = CollectionFilters()
        filters.types = ["land", "instant"]
        #expect(names(filters) == ["Forest", "Putrefy"])
    }

    @Test func placesDecksAndNoPlace() {
        var filters = CollectionFilters()
        filters.places = ["place:binder"]
        #expect(names(filters) == ["Sol Ring", "Putrefy"])  // "binder" and "Binder" are one place
        let sol = Self.library.collectionGroups(filters: filters).first { $0.name == "Sol Ring" }
        #expect(sol?.entries.map(\.id) == ["c1"] && sol?.copies == 2)  // only the entries that match
        filters.places = ["deck:meren"]
        #expect(names(filters) == ["Forest"])
        filters.places = ["none"]
        #expect(names(filters) == ["Llanowar Elves", "Putrefy"])
        filters.places = ["free"]  // everything not sleeved up in a deck
        #expect(!names(filters).contains("Forest") && names(filters).count == 3)
    }

    @Test func setLanguageAndValue() {
        var filters = CollectionFilters()
        filters.sets = ["c21", "gpt"]
        #expect(names(filters) == ["Sol Ring", "Putrefy"])  // in the list's order (the test added Putrefy last)
        filters = CollectionFilters()
        filters.languages = ["de"]
        #expect(names(filters) == ["Llanowar Elves"])
        filters = CollectionFilters()
        filters.minValue = 5
        let rich = Self.library.collectionGroups(filters: filters)
        #expect(rich.map(\.name) == ["Putrefy"] && rich[0].entries.map(\.id) == ["p2"])  // the proxy is worth nothing
    }

    @Test func kindsCombine() {
        var filters = CollectionFilters()
        filters.colors = ["B", "G"]
        filters.places = ["none"]
        filters.minValue = 1
        #expect(names(filters) == ["Putrefy"])
    }

    @Test func sorting() {
        #expect(names(CollectionFilters(), sort: .value) == ["Putrefy", "Sol Ring", "Llanowar Elves", "Forest"])
        #expect(names(CollectionFilters(), sort: .copies) == ["Forest", "Llanowar Elves", "Sol Ring", "Putrefy"])
        #expect(names(CollectionFilters(), sort: .set) == ["Sol Ring", "Putrefy", "Llanowar Elves", "Forest"])
    }

    @Test func choicesAreOnlyWhatTheCollectionHas() {
        let choices = Self.library.collectionChoices
        #expect(choices.decks.map(\.slug) == ["meren"])
        #expect(choices.places == ["Binder", "Kiste"])
        #expect(choices.sets.map(\.code) == ["c21", "dis", "fdn", "gpt"])
        #expect(choices.languages == ["en", "de"])
    }

    @Test func summaryInWords() {
        var filters = CollectionFilters()
        filters.colors = ["G", "B"]
        filters.types = ["creature"]
        filters.places = ["deck:meren", "place:binder"]
        filters.minValue = 5
        let library = Self.library
        let meren = library.decks.first { $0.slug == "meren" }!.name
        #expect(filters.summary(decks: library.decks, places: library.knownPlaces)
            == "Black or Green · Creature · in \(meren) or in Binder · over 5 €")
        #expect(CollectionFilters().isEmpty && !filters.isEmpty && filters.needsCards)
    }
}
