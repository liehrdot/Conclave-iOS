import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// One line of text the camera read, with where it sits in the card frame: 0…1 from the frame's left
/// and top edge, so the reader needn't know the screen. The scanner screen turns VisionKit's corners into this.
public struct ReadLine: Equatable, Sendable {
    public var text: String
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(_ text: String, x: Double = 0, y: Double = 0, width: Double = 1, height: Double = 0.05) {
        self.text = text
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    var midY: Double { y + height / 2 }

    /// A line the camera found at `points` (its corners, in the screen's points), placed in the card frame
    /// `frame` on the same screen. A tilted line gets the box around its corners.
    public init(_ text: String, points: [CGPoint], frame: CGRect) {
        let xs: [Double] = points.map { Double($0.x) }, ys: [Double] = points.map { Double($0.y) }
        let minX: Double = xs.min() ?? 0, minY: Double = ys.min() ?? 0
        let maxX: Double = xs.max() ?? 0, maxY: Double = ys.max() ?? 0
        let left = Double(frame.minX), top = Double(frame.minY)
        let w: Double = max(Double(frame.width), 1), h: Double = max(Double(frame.height), 1)
        self.init(text, x: (minX - left) / w, y: (minY - top) / h, width: (maxX - minX) / w, height: (maxY - minY) / h)
    }

    /// Where the line is on the screen again, for the overlay.
    public func rect(in frame: CGRect) -> CGRect {
        let w = Double(frame.width), h = Double(frame.height)
        return CGRect(x: Double(frame.minX) + x * w, y: Double(frame.minY) + y * h, width: width * w, height: height * h)
    }
}

/// The card-shaped cutout the scanner asks for: 63 × 88 mm like a card, as large as fits in a
/// screen of `size` with room around it for the bars and the status, a little above the middle.
public enum CardFrame {
    public static let aspect = 63.0 / 88.0

    public static func rect(in size: CGSize, top: Double = 0, bottom: Double = 0) -> CGRect {
        let screenWidth = Double(size.width), screenHeight = Double(size.height)
        let room: Double = max(screenHeight - top - bottom, 1)
        let width: Double = min(screenWidth * 0.84, room * 0.86 * aspect)
        let height: Double = width / aspect
        return CGRect(x: (screenWidth - width) / 2, y: top + (room - height) * 0.45, width: width, height: height)
    }
}

/// The set line at the bottom left: "MKM • DE" and the collector number of cards since 2015, or older
/// "123/280 R" + "M20 • EN".
public struct SetLine: Equatable, Sendable {
    public var set: String
    /// "" when the number wasn't read.
    public var number: String
    public var lang: String

    public init(set: String, number: String = "", lang: String = "en") {
        self.set = set
        self.number = number
        self.lang = lang
    }

    /// The language codes printed on cards, as Scryfall writes them (`LANGS` in `scan.js`).
    static let languages = ["EN": "en", "DE": "de", "FR": "fr", "IT": "it", "ES": "es", "SP": "es", "PT": "pt", "JP": "ja",
                            "JA": "ja", "KO": "ko", "RU": "ru", "CS": "zhs", "CT": "zht", "PH": "ph"]

    /// "0123 R\nMKM • DE ✒ Artist" → mkm #123 de. The set code is 3–5 letters and digits with at least one
    /// letter, then a language code; the number is the digits closest before it (or "123/280" after it on
    /// older cards), leading zeros gone. Mirrors `parseLine()` in `scan.js`, except that it takes the closest
    /// number, not the first: a power/toughness read above the set line ("12/12") isn't the number.
    public static func parse(_ text: String) -> SetLine? {
        let t = withoutCopyright(text.uppercased().replacingOccurrences(of: "|", with: "I"))
        let codes = languages.keys.joined(separator: "|")
        let pattern = #"\b([A-Z0-9]{3,5})\s{0,4}(?:[^A-Z0-9\s]{1,2}\s{0,4})?("# + codes + #")\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let m = regex.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)),
              let setRange = Range(m.range(at: 1), in: t), let langRange = Range(m.range(at: 2), in: t),
              let whole = Range(m.range, in: t) else { return nil }
        let set = String(t[setRange])
        guard set.contains(where: \.isLetter) else { return nil }
        let before = String(t[..<whole.lowerBound]), after = String(t[whole.upperBound...])
        let number = number(before, #"\b0*(\d{1,4})(?:\s*/\s*\d{1,4})?\b"#, last: true)
            ?? number(after, #"\b0*(\d{1,4})\s*/\s*\d{1,4}\b"#, last: false) ?? ""
        return SetLine(set: set.lowercased(), number: number, lang: languages[String(t[langRange])] ?? "en")
    }

    /// "™ & © 2017 Wizards of the Coast" sits next to the set line and its year is no collector number: a year
    /// after ©, & or ™ (also as Vision reads them: "@", "(C)") or before "Wizards" goes.
    static func withoutCopyright(_ text: String) -> String {
        let pattern = #"(?:[©@&™]|\(C\)|\bTM\b)\s{0,3}(?:19|20)\d{2}\b|\b(?:19|20)\d{2}(?=\s{0,3}WIZ)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        return regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: " ")
    }

    private static func number(_ text: String, _ pattern: String, last: Bool) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        guard let m = last ? matches.last : matches.first, let range = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }
}

/// What a camera frame shows, as text: the name candidates from the top of the card and the set line
/// from the bottom. Mirrors `readCard()` in `scan.js`, minus the cutting out (Vision reads the whole
/// frame and says where each line is).
public struct CardRead: Equatable, Sendable {
    public var names: [String]
    public var line: SetLine?
    /// The lines each part came from, for the scanner's overlay.
    public var nameLine: ReadLine?
    public var setLine: ReadLine?

    /// Nothing card-like was read: the card has left the frame.
    public var isEmpty: Bool { names.isEmpty && (line?.number ?? "").isEmpty }

    /// Where the parts are looked for, as parts of the frame's height: the top fifth (the name bar) and
    /// the bottom sixth (the set line), a little beyond the frame, as cards are rarely held exactly in it.
    static let top = -0.03...0.22
    static let bottom = 0.82...1.04

    public init(names: [String] = [], line: SetLine? = nil, nameLine: ReadLine? = nil, setLine: ReadLine? = nil) {
        self.names = names
        self.line = line
        self.nameLine = nameLine
        self.setLine = setLine
    }

    /// Picks the name candidates (the top lines that look like words, top first, at most four) and the set
    /// line (the bottom lines read together, as the number and the set code sit on two lines).
    public init(_ lines: [ReadLine]) {
        let ordered = lines.sorted { $0.midY < $1.midY }
        var names: [String] = []
        var nameLine: ReadLine?
        for line in ordered where Self.top.contains(line.midY) {
            let name = Self.cleanName(line.text)
            guard name.count >= 3, Self.hasLetters(name, 3), !names.contains(name) else { continue }
            names.append(name)
            if nameLine == nil { nameLine = line }
        }
        let bottom = ordered.filter { Self.bottom.contains($0.midY) && $0.x < 0.75 && !Self.isPowerToughness($0.text) }
        let set = SetLine.parse(bottom.map(\.text).joined(separator: "\n"))
        let setLine = set.flatMap { found in bottom.first { $0.text.uppercased().contains(found.set.uppercased()) } }
        self.init(names: Array(names.prefix(4)), line: set, nameLine: nameLine, setLine: setLine)
    }

    /// "Sol Rinq @" → "Sol Rinq": letters (also accented), spaces, apostrophes, commas and hyphens; stray
    /// symbols at the ends (a mana symbol read as letters) go. Mirrors `cleanName()` in `scan.js`.
    public static func cleanName(_ text: String) -> String {
        let line = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.max { $0.count < $1.count } ?? ""
        let kept = String(line.map { c -> Character in
            let c: Character = "’`´".contains(c) ? "'" : c
            return c.isLetter || " ',-".contains(c) ? c : " "
        })
        var words = kept.split(whereSeparator: \.isWhitespace).map(String.init)
        while let first = words.first, !hasLetters(first, 2) { words.removeFirst() }
        while let last = words.last, !hasLetters(last, 2) { words.removeLast() }
        return words.joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: ",'-")).trimmingCharacters(in: .whitespaces)
    }

    /// "12/12", "*/*", "1/1+": the power/toughness box, which sits right above the set line and looks like an
    /// old collector number. A real old number has its rarity letter next to it ("123/280 R").
    static func isPowerToughness(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespaces).range(of: #"^[\dX*+]{1,3}\s*/\s*[\dX*+]{1,3}$"#, options: .regularExpression) != nil
    }

    static func hasLetters(_ text: String, _ count: Int) -> Bool {
        var run = 0
        for c in text {
            run = c.isLetter ? run + 1 : 0
            if run >= count { return true }
        }
        return false
    }
}

/// The lookups the reader needs, so tests can answer them without Scryfall.
public protocol CardLookup: Sendable {
    func printing(set: String, number: String, lang: String) async throws -> Printing?
    func printing(named name: String, set: String) async throws -> Printing?
    func printings(printedName: String) async throws -> [Printing]
}

extension Scryfall: CardLookup {
    /// Printings whose printed name (German, …) or text matches, newest first, at most 60. Mirrors
    /// `byPrintedName()` in `scry.js`; a failure is no hits.
    public func printings(printedName: String) async throws -> [Printing] {
        let items = [URLQueryItem(name: "q", value: printedName), URLQueryItem(name: "include_multilingual", value: "true"),
                     URLQueryItem(name: "unique", value: "prints"), URLQueryItem(name: "order", value: "released"),
                     URLQueryItem(name: "dir", value: "desc")]
        struct Answer: Decodable { var data: [ScryfallCard] }
        guard let data = try? await send(URLRequest(url: Self.url("cards/search", items))),
              let answer = try? Self.decoder.decode(Answer.self, from: data) else { return [] }
        return Array(answer.data.prefix(60).compactMap(\.printing))
    }
}

/// A card the reader found: the printing, whether it needs no second look, and what it was found by.
public struct ReadHit: Equatable, Sendable {
    public var printing: Printing
    /// Sure enough to open the add sheet at once; else the same card must come twice in a row.
    public var sure: Bool
    /// Found by set + number (the exact printing), not only by the name.
    public var bySet: Bool
    /// The text it was found by ("" for the set line alone).
    public var read: String
}

/// Turns what the camera read into a card, the way the web app's scanner does (`identify()` and
/// `identifyRead()` in `scan.js`): the set line first, checked against the name; else the name with
/// Scryfall's fuzzy search, in that set first; else a German (or other) printed name. Each text is asked
/// once. An actor, so the scanner's frames can share its memory.
public actor CardReader {
    let lookup: any CardLookup
    private var asked: [String: Printing?] = [:]
    private var askedPrinted: [String: [Printing]] = [:]

    public init(lookup: any CardLookup) {
        self.lookup = lookup
    }

    /// The card a frame shows, or nil. The names are tried in order; the set line alone (no name read) still
    /// finds a printing, but not a sure one.
    public func identify(_ read: CardRead) async -> ReadHit? {
        for name in read.names {
            if let hit = await identify(name: name, line: read.line) { return hit }
        }
        if let line = read.line, !line.number.isEmpty { return await identify(name: "", line: line) }
        return nil
    }

    func identify(name: String, line: SetLine?) async -> ReadHit? {
        var bySet: Printing?
        if let line, !line.number.isEmpty {
            bySet = await once("#\(line.set)/\(line.number)/\(line.lang)") { [lookup] in
                if let found = try await lookup.printing(set: line.set, number: line.number, lang: line.lang) { return found }
                return line.lang == "en" ? nil : try await lookup.printing(set: line.set, number: line.number, lang: "en")
            }
            // agrees with the name, or the name is a cut-off piece of it ("Fight" from "Rejoin the Fight")
            if let bySet {
                let piece = Self.norm(name).count >= 4 && [bySet.name, bySet.printedName].contains {
                    $0.map { Self.norm($0).contains(Self.norm(name)) } ?? false
                }
                if piece || Self.similar(name, bySet) >= 0.45 { return ReadHit(printing: bySet, sure: true, bySet: true, read: name) }
            }
        }
        // a set line that disagrees with a clearly read name was misread: the name wins
        guard name.count >= 3 else { return bySet.map { ReadHit(printing: $0, sure: false, bySet: true, read: name) } }
        let set = line?.set ?? ""
        let named = await once("\(name)|\(set)") { [lookup] in
            if !set.isEmpty, let inSet = try await lookup.printing(named: name, set: set) { return inSet }
            return try await lookup.printing(named: name, set: "")
        }
        if let named, Self.similar(name, named) >= 0.7 {
            return ReadHit(printing: named, sure: Self.similar(name, named) >= 0.85, bySet: false, read: name)
        }
        // a German (or other) printed name; a misread letter fails Scryfall's search, so its longest word is asked too
        guard name.count >= 5 else { return nil }
        var list = await printed(name)
        let word = name.split { " -,".contains($0) }.map(String.init).max { $0.count < $1.count } ?? ""
        if list.isEmpty, word.count >= 6, word != name { list = await printed(word) }
        guard let best = list.max(by: { Self.similar(name, $0) < Self.similar(name, $1) }), Self.similar(name, best) >= 0.75 else { return nil }
        return ReadHit(printing: best, sure: Self.similar(name, best) >= 0.85, bySet: false, read: name)
    }

    private func once(_ key: String, _ ask: @Sendable () async throws -> Printing?) async -> Printing? {
        if let known = asked[key] { return known }
        do {
            let found = try await ask()
            asked[key] = .some(found)  // "no such card" is remembered too
            return found
        } catch {
            return nil  // a failed request is asked again next frame
        }
    }

    private func printed(_ text: String) async -> [Printing] {
        if let known = askedPrinted[text] { return known }
        let found = (try? await lookup.printings(printedName: text)) ?? []
        askedPrinted[text] = found
        return found
    }

    // MARK: - How alike two names are

    /// Lowercase letters and digits only, accents dropped ("Æther-Vial" → "aethervial" is close enough).
    static func norm(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }

    /// 1 − the edit distance over the longer length: 1 is the same, 0 nothing alike. Mirrors `ratio()`.
    static func ratio(_ a: String, _ b: String) -> Double {
        let a = Array(norm(a)), b = Array(norm(b))
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var diagonal = previous[0]
            previous[0] = i
            for j in 1...b.count {
                let up = previous[j]
                previous[j] = min(previous[j] + 1, previous[j - 1] + 1, diagonal + (a[i - 1] == b[j - 1] ? 0 : 1))
                diagonal = up
            }
        }
        return 1 - Double(previous[b.count]) / Double(max(a.count, b.count))
    }

    /// How well a read name fits a printing: its English name, its printed name, either face. A long piece
    /// of a name counts too (the first word is often cut off when the card sits askew). Mirrors `similar()`.
    static func similar(_ text: String, _ printing: Printing) -> Double {
        let whole = [printing.name, printing.printedName].compactMap { $0 }
        let faces = whole.flatMap { $0.components(separatedBy: " // ") }.filter { !whole.contains($0) }
        let names = whole + faces
        let t = norm(text)
        return names.map { n in
            t.count >= 8 && norm(n).contains(t) ? max(0.8, ratio(text, n)) : ratio(text, n)
        }.max() ?? 0
    }
}

/// The scanner's patience: a sure hit opens the add sheet at once, a doubtful one only when the same
/// printing comes twice in a row; the card just added is skipped until the frame is empty. Mirrors the
/// `tick()` loop in `scan.js`.
public struct ScanSteadiness: Equatable, Sendable {
    private var last: String?
    /// The card the last name-read hit showed (its Oracle id), while the card stays in the frame: a hit by
    /// the set line alone that says otherwise is a misread number, not a new card.
    private var named: String?
    /// The card added last (its Oracle id); nil once the card left the frame.
    public private(set) var ignored: String?

    public init() {}

    public enum Outcome: Equatable, Sendable {
        /// Show it: open the add sheet.
        case found(Printing)
        /// Seen once, not sure yet: show it as "Sol Ring?".
        case maybe(Printing)
        /// The card just added is still in the frame.
        case alreadyAdded
        case nothing
    }

    /// One frame's result.
    public mutating func next(_ read: CardRead, _ hit: ReadHit?) -> Outcome {
        if read.isEmpty {
            ignored = nil  // the card left the frame: the same card may come again
            named = nil
            return .nothing
        }
        guard let hit else { return .nothing }
        if hit.read.isEmpty {
            if let named, named != hit.printing.oracleID { return .nothing }
        } else {
            named = hit.printing.oracleID
        }
        if hit.printing.oracleID == ignored { return .alreadyAdded }
        if hit.sure || last == hit.printing.id {
            last = nil
            return .found(hit.printing)
        }
        last = hit.printing.id
        return .maybe(hit.printing)
    }

    /// The card went into the collection: skip it until the frame is empty.
    public mutating func added(_ printing: Printing) {
        ignored = printing.oracleID
        last = nil
    }
}
