import Foundation
import Testing
@testable import ConclaveCore

@Suite struct CardReaderTests {
    // MARK: - The set line

    @Test func setLinesOfNewCards() {
        #expect(SetLine.parse("0283 R\nMH3 • EN ✒ Artist") == SetLine(set: "mh3", number: "283", lang: "en"))
        #expect(SetLine.parse("0141 M\nNEO • DE") == SetLine(set: "neo", number: "141", lang: "de"))
        #expect(SetLine.parse("MKM * SP") == SetLine(set: "mkm", lang: "es"))  // the number wasn't read
        #expect(SetLine.parse("0007 C\nWOE  JP")?.lang == "ja")
        #expect(SetLine.parse("0012 U\nM|D • EN")?.set == "mid")  // a misread I
    }

    @Test func setLinesOfOlderCards() {
        #expect(SetLine.parse("123/280 R\nM20 • EN") == SetLine(set: "m20", number: "123", lang: "en"))
        #expect(SetLine.parse("M20 • EN\n045/280 C") == SetLine(set: "m20", number: "45", lang: "en"))  // the number after it
    }

    @Test func noSetLine() {
        #expect(SetLine.parse("Tap: Add two mana") == nil)
        #expect(SetLine.parse("123 EN") == nil)  // a set code has a letter
        #expect(SetLine.parse("") == nil)
    }

    // MARK: - Names

    @Test func cleanNames() {
        #expect(CardRead.cleanName("Sol Ring ①") == "Sol Ring")
        #expect(CardRead.cleanName("® Llanowar Elves 6") == "Llanowar Elves")
        #expect(CardRead.cleanName("Urza’s Saga") == "Urza's Saga")
        #expect(CardRead.cleanName("x\nAshnod's Altar\ny") == "Ashnod's Altar")  // the longest line
        #expect(CardRead.cleanName("Sengir, der Dunkle Baron -") == "Sengir, der Dunkle Baron")
        #expect(CardRead.cleanName("@ 3 !") == "")
    }

    @Test func aFrameIsSplitIntoNamesAndTheSetLine() {
        let read = CardRead([
            ReadLine("Creature — Elf Druid", y: 0.55),
            ReadLine("Llanowar Elves ⓖ", y: 0.05),
            ReadLine("0274 C", x: 0.05, y: 0.9, width: 0.2, height: 0.02),
            ReadLine("FDN • EN Artist", x: 0.05, y: 0.93, width: 0.4, height: 0.02),
            ReadLine("1/1", x: 0.85, y: 0.9, width: 0.1, height: 0.03),  // power/toughness at the right: not the set line
            ReadLine("ee", y: 0.1),
        ])
        #expect(read.names == ["Llanowar Elves"])
        #expect(read.line == SetLine(set: "fdn", number: "274", lang: "en"))
        #expect(read.nameLine?.text == "Llanowar Elves ⓖ" && read.setLine?.text == "FDN • EN Artist")
        #expect(!read.isEmpty && CardRead([ReadLine("Flying", y: 0.6)]).isEmpty)
    }

    @Test func screenPointsBecomeFramePlaces() {
        let frame = CGRect(x: 40, y: 100, width: 300, height: 420)
        let line = ReadLine("Sol Ring", points: [CGPoint(x: 70, y: 121), CGPoint(x: 190, y: 115), CGPoint(x: 70, y: 142), CGPoint(x: 190, y: 136)], frame: frame)
        #expect(abs(line.x - 0.1) < 1e-9 && abs(line.y - 15.0 / 420) < 1e-9)
        #expect(abs(line.width - 0.4) < 1e-9 && abs(line.height - 27.0 / 420) < 1e-9)
        #expect(line.rect(in: frame).integral == CGRect(x: 70, y: 115, width: 120, height: 27))
    }

    @Test func theCutoutIsCardShapedAndFits() {
        let phone = CardFrame.rect(in: CGSize(width: 393, height: 852), top: 100, bottom: 160)
        #expect(abs(phone.width / phone.height - CardFrame.aspect) < 1e-9)
        #expect(phone.minX >= 0 && phone.maxX <= 393 && phone.minY >= 100 && phone.maxY <= 852 - 160)
        let wide = CardFrame.rect(in: CGSize(width: 1194, height: 834))  // an iPad on its side: the height decides
        #expect(wide.height <= 834 && abs(wide.midX - 597) < 1e-9)
    }

    // MARK: - Finding the card

    static let elves = Printing(id: "elves-fdn", oracleID: "elves", name: "Llanowar Elves", set: "fdn", collectorNumber: "274")
    static let elvesDE = Printing(id: "elves-fdn-de", oracleID: "elves", name: "Llanowar Elves", printedName: "Llanowarelfen",
                                  lang: "de", set: "fdn", collectorNumber: "274")
    static let fight = Printing(id: "fight", oracleID: "fight", name: "Rejoin the Fight", set: "mh3", collectorNumber: "99")
    static let fable = Printing(id: "fable", oracleID: "fable", name: "Fable of the Mirror-Breaker // Reflection of Kiki-Jiki",
                                set: "neo", collectorNumber: "141")

    /// Scryfall as far as the tests need it, counting what was asked.
    final class Lookup: CardLookup, @unchecked Sendable {
        var bySet: [String: Printing] = [:]
        var byName: [String: Printing] = [:]
        var byPrinted: [String: [Printing]] = [:]
        var fails = false
        private(set) var asked: [String] = []
        private let lock = NSLock()

        private func note(_ text: String) throws {
            lock.withLock { asked.append(text) }
            if fails { throw URLError(.notConnectedToInternet) }
        }

        func printing(set: String, number: String, lang: String) async throws -> Printing? {
            try note("set \(set)/\(number)/\(lang)")
            return bySet["\(set)/\(number)/\(lang)"]
        }

        func printing(named name: String, set: String) async throws -> Printing? {
            try note("named \(name)|\(set)")
            return byName[set.isEmpty ? name.lowercased() : "\(name.lowercased())|\(set)"]
        }

        func printings(printedName: String) async throws -> [Printing] {
            try note("printed \(printedName)")
            return byPrinted[printedName] ?? []
        }
    }

    @Test func theSetLineFindsTheExactPrinting() async {
        let lookup = Lookup()
        lookup.bySet["fdn/274/en"] = Self.elves
        let reader = CardReader(lookup: lookup)
        let hit = await reader.identify(CardRead(names: ["Llanowar Elvas"], line: SetLine(set: "fdn", number: "274")))
        #expect(hit == ReadHit(printing: Self.elves, sure: true, bySet: true, read: "Llanowar Elvas"))
        // a cut-off piece of the name agrees too
        lookup.bySet["mh3/99/en"] = Self.fight
        #expect(await reader.identify(CardRead(names: ["Fight"], line: SetLine(set: "mh3", number: "99")))?.sure == true)
        // no name read: the set line alone, but not sure
        let alone = await reader.identify(CardRead(line: SetLine(set: "fdn", number: "274")))
        #expect(alone?.printing == Self.elves && alone?.sure == false)
    }

    @Test func aGermanSetLineFallsBackToEnglish() async {
        let lookup = Lookup()
        lookup.bySet["fdn/274/en"] = Self.elves
        let hit = await CardReader(lookup: lookup).identify(CardRead(names: ["Llanowarelfen"], line: SetLine(set: "fdn", number: "274", lang: "de")))
        #expect(hit?.printing == Self.elves && lookup.asked.prefix(2) == ["set fdn/274/de", "set fdn/274/en"])
    }

    @Test func aMisreadSetLineLosesToTheName() async {
        let lookup = Lookup()
        lookup.bySet["fdn/247/en"] = Self.fight  // the digits swapped: another card
        lookup.byName["llanowar elves|fdn"] = Self.elves
        let hit = await CardReader(lookup: lookup).identify(CardRead(names: ["Llanowar Elves"], line: SetLine(set: "fdn", number: "247")))
        #expect(hit == ReadHit(printing: Self.elves, sure: true, bySet: false, read: "Llanowar Elves"))
    }

    @Test func byNameInTheSetFirstThenAnywhere() async {
        let lookup = Lookup()
        lookup.byName["llanowar elvs"] = Self.elves
        let hit = await CardReader(lookup: lookup).identify(CardRead(names: ["Llanowar Elvs"], line: SetLine(set: "xyz")))
        #expect(hit?.printing == Self.elves && hit?.sure == true)
        #expect(lookup.asked == ["named Llanowar Elvs|xyz", "named Llanowar Elvs|"])
    }

    @Test func aWeakNameMatchIsNotSure() async {
        let lookup = Lookup()
        lookup.byName["lanowar elvs"] = Self.elves  // Scryfall's fuzzy search is generous
        let hit = await CardReader(lookup: lookup).identify(CardRead(names: ["Lanowar Elvs"]))
        #expect(hit?.printing == Self.elves && hit?.sure == false)
        lookup.byName["sol"] = Self.elves  // far off: no hit
        #expect(await CardReader(lookup: lookup).identify(CardRead(names: ["Sol"])) == nil)
    }

    @Test func germanNamesAndTheirLongestWord() async {
        let lookup = Lookup()
        lookup.byPrinted["Llanowarelfen"] = [Self.elvesDE]
        let hit = await CardReader(lookup: lookup).identify(CardRead(names: ["Llanowarelfen"]))
        #expect(hit?.printing == Self.elvesDE && hit?.sure == true)
        // a misread letter: Scryfall finds nothing for the whole text, so the longest word is asked
        let kodama = Printing(id: "kodama-de", oracleID: "kodama", name: "Kodama of the North Tree", printedName: "Kodama des Nordbaums",
                              lang: "de", set: "chk", collectorNumber: "222")
        lookup.byPrinted["Nordbaums"] = [kodama]
        let misread = await CardReader(lookup: lookup).identify(CardRead(names: ["Kodoma des Nordbaums"]))
        #expect(misread?.printing == kodama && lookup.asked.suffix(2) == ["printed Kodoma des Nordbaums", "printed Nordbaums"])
    }

    @Test func eachTextIsAskedOnceUnlessItFailed() async {
        let lookup = Lookup()
        lookup.byName["llanowar elves"] = Self.elves
        let reader = CardReader(lookup: lookup)
        let read = CardRead(names: ["Llanowar Elves"])
        _ = await reader.identify(read)
        _ = await reader.identify(read)
        #expect(lookup.asked.filter { $0.hasPrefix("named") }.count == 1)
        // nothing found is remembered as well
        _ = await reader.identify(CardRead(names: ["Qqqq Zzzz"]))
        let asked = lookup.asked.count
        _ = await reader.identify(CardRead(names: ["Qqqq Zzzz"]))
        #expect(lookup.asked.count == asked)
        // a failed request is not
        lookup.fails = true
        let offline = CardReader(lookup: lookup)
        #expect(await offline.identify(read) == nil)
        lookup.fails = false
        #expect(await offline.identify(read)?.printing == Self.elves)
    }

    @Test func similarLooksAtBothFacesAndThePrintedName() {
        #expect(CardReader.similar("Reflection of Kiki-Jiki", Self.fable) == 1)
        #expect(CardReader.similar("Fable of the Mirror Breaker", Self.fable) == 1)
        #expect(CardReader.similar("Llanowarelfen", Self.elvesDE) == 1)
        #expect(CardReader.similar("Mirror-Breaker", Self.fable) >= 0.8)  // a long piece of a face
        #expect(CardReader.similar("Sol Ring", Self.elves) < 0.3)
        #expect(CardReader.ratio("Lim-Dul's Vault", "Lim-Dûl’s Vault") == 1)  // accents and punctuation don't count
    }

    // MARK: - Patience

    @Test func aDoubtfulHitMustComeTwice() {
        var steady = ScanSteadiness()
        let read = CardRead(names: ["Lanowar Elvs"])
        let weak = ReadHit(printing: Self.elves, sure: false, bySet: false, read: "Lanowar Elvs")
        #expect(steady.next(read, weak) == .maybe(Self.elves))
        #expect(steady.next(read, weak) == .found(Self.elves))
        #expect(steady.next(read, nil) == .nothing)
        #expect(steady.next(read, ReadHit(printing: Self.fight, sure: true, bySet: true, read: "")) == .found(Self.fight))
    }

    @Test func theCardJustAddedWaitsForAnEmptyFrame() {
        var steady = ScanSteadiness()
        let read = CardRead(names: ["Llanowar Elves"])
        let hit = ReadHit(printing: Self.elves, sure: true, bySet: false, read: "Llanowar Elves")
        steady.added(Self.elves)
        #expect(steady.next(read, hit) == .alreadyAdded)
        // another printing of the same card is the same card
        #expect(steady.next(read, ReadHit(printing: Self.elvesDE, sure: true, bySet: true, read: "")) == .alreadyAdded)
        #expect(steady.next(CardRead(), nil) == .nothing)
        #expect(steady.next(read, hit) == .found(Self.elves))
    }
}
