import Testing
@testable import ConclaveCore

@Suite struct CardFilterTests {
    @Test func noFilterKeepsTheNameSearch() {
        #expect(CardFilter().isEmpty)
        #expect(CardFilter().query(name: "Sol") == nil)
    }

    @Test func aRoleWithoutANameListsWhatFits() {
        #expect(CardFilter(role: "otag:ramp").query(name: "  ") == "otag:ramp f:commander")
    }

    @Test func nameRoleColoursAndTypesTogether() {
        let filter = CardFilter(role: "otag:removal", colors: ["G", "B"], types: ["instant"])
        #expect(filter.query(name: "Assassin") == "Assassin otag:removal id<=bg -id:c t:instant f:commander")
    }

    /// The same rules as the server's `compose()` in `cardsearch.py`.
    @Test func colourlessAndSeveralTypes() {
        #expect(CardFilter.compose("", colors: ["C"]) == "id:c f:commander")
        #expect(CardFilter.compose("", colors: ["W", "C"]) == "id<=w f:commander")
        #expect(CardFilter.compose("", types: ["land", "creature"]) == "(t:creature OR t:land) f:commander")
        #expect(CardFilter.compose("a or b") == "(a or b) f:commander")
    }
}
