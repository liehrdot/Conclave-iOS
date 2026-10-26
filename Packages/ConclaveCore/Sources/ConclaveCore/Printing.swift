import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// One printing of a card, in one language: what a collection entry records about the copy in your
/// hand. Scryfall's card object, the keys `entryFacts()` in the PWA's `scry.js` reads.
public struct Printing: Equatable, Sendable, Identifiable, Hashable {
    /// Scryfall's id of this printing.
    public var id: String
    /// The card across all its printings (`oracleid:` in a search).
    public var oracleID: String
    /// The English (Oracle) name.
    public var name: String
    /// The name printed on the card when it isn't English ("Seelenwächter").
    public var printedName: String?
    public var lang: String
    public var set: String
    public var setName: String
    public var collectorNumber: String
    /// "2024-08-02".
    public var released: String
    /// "nonfoil", "foil", "etched": how this printing was made.
    public var finishes: [String]
    public var image: URL?
    /// The back of a double-faced card.
    public var imageBack: URL?
    /// Scryfall's prices as it gives them ("1.20"), per currency and finish ("eur", "eur_foil", "usd", …).
    public var prices: [String: String]

    public init(id: String, oracleID: String = "", name: String, printedName: String? = nil, lang: String = "en",
                set: String, setName: String = "", collectorNumber: String, released: String = "",
                finishes: [String] = ["nonfoil", "foil"], image: URL? = nil, imageBack: URL? = nil, prices: [String: String] = [:]) {
        self.id = id
        self.oracleID = oracleID
        self.name = name
        self.printedName = printedName
        self.lang = lang
        self.set = set
        self.setName = setName
        self.collectorNumber = collectorNumber
        self.released = released
        self.finishes = finishes
        self.image = image
        self.imageBack = imageBack
        self.prices = prices
    }

    /// The name as printed: the German one on a German card, else the English one.
    public var shownName: String { printedName.flatMap { $0.isEmpty || $0 == name ? nil : $0 } ?? name }

    /// Whether the printing comes without foil, and with foil (or etched foil).
    public var hasNonfoil: Bool { finishes.isEmpty || finishes.contains("nonfoil") }
    public var hasFoil: Bool { finishes.isEmpty || finishes.contains { $0 != "nonfoil" } }

    /// The price of one copy in `currency` ("eur", "usd"), the foil price for a foil; the other finish's
    /// price when this one has none. Mirrors `price()` in `entryFacts()`.
    public func price(_ currency: String = "eur", foil: Bool = false) -> String? {
        let plain = prices[currency], shiny = prices["\(currency)_foil"]
        return foil ? shiny ?? plain : plain ?? shiny
    }
}

extension ScryfallCard {
    var printing: Printing? {
        guard let id, let set, let collectorNumber else { return nil }
        let images = imageUris ?? cardFaces?.first?.imageUris
        return Printing(id: id, oracleID: oracleId ?? "", name: name, printedName: printedName, lang: lang ?? "en",
                        set: set, setName: setName ?? set.uppercased(), collectorNumber: collectorNumber,
                        released: releasedAt ?? "", finishes: finishes ?? [], image: images?.normal,
                        imageBack: imageUris == nil ? cardFaces?.dropFirst().first?.imageUris?.normal : nil,
                        prices: (prices ?? [:]).compactMapValues { $0 })
    }
}

extension Scryfall {
    /// One printing by set code and collector number, in `lang` when it isn't English; nil when Scryfall
    /// has none. Mirrors `printing()` in `scry.js`.
    public func printing(set: String, number: String, lang: String = "en") async throws -> Printing? {
        var url = Self.api.appending(path: "cards").appending(path: set.lowercased()).appending(path: number)
        if lang != "en", !lang.isEmpty { url = url.appending(path: lang) }
        return try await lookUp(URLRequest(url: url))
    }

    /// A name with typos or missing letters (English), in one set when given; nil when Scryfall can't
    /// tell which card. Mirrors `named()` in `scry.js`.
    public func printing(named name: String, set: String = "") async throws -> Printing? {
        var items = [URLQueryItem(name: "fuzzy", value: name)]
        if !set.isEmpty { items.append(URLQueryItem(name: "set", value: set.lowercased())) }
        return try await lookUp(URLRequest(url: Self.url("cards/named", items)))
    }

    /// Every paper printing of a card, newest first, at most three pages: English only, or with `anyLanguage`
    /// the others too. Mirrors `prints()` in `scry.js`, for "Other Printing".
    public func printings(of oracleID: String, anyLanguage: Bool = false) async throws -> [Printing] {
        var out: [Printing] = []
        var page = 1
        while page <= 3 {
            var items = [URLQueryItem(name: "q", value: "oracleid:\(oracleID)\(anyLanguage ? "" : " lang:en") game:paper"),
                         URLQueryItem(name: "unique", value: "prints"), URLQueryItem(name: "order", value: "released"),
                         URLQueryItem(name: "dir", value: "desc"), URLQueryItem(name: "page", value: String(page))]
            if anyLanguage { items.append(URLQueryItem(name: "include_multilingual", value: "true")) }
            struct Answer: Decodable { var data: [ScryfallCard]; var hasMore: Bool? }
            let data: Data
            do {
                data = try await send(URLRequest(url: Self.url("cards/search", items)))
            } catch CardError.failed(status: 404) {
                break
            }
            guard let answer = try? Self.decoder.decode(Answer.self, from: data) else { throw CardError.failed(status: 200) }
            out += answer.data.compactMap(\.printing)
            guard answer.hasMore == true else { break }
            page += 1
        }
        return out
    }

    /// A card object, or nil when Scryfall answers 404 (no such card).
    private func lookUp(_ request: URLRequest) async throws -> Printing? {
        do {
            return try Self.decoder.decode(ScryfallCard.self, from: try await send(request)).printing
        } catch CardError.failed(status: 404) {
            return nil
        }
    }
}

/// The "Add to Collection" sheet's choices and the `collection.add` they make. Mirrors `addSheet()` in the
/// PWA's `scan.js`.
public struct CollectionAddDraft: Equatable, Sendable {
    public private(set) var printing: Printing
    public var proxy: Bool
    public private(set) var foil: Bool
    /// The language of the copy in your hand; the printing follows it when Scryfall has that language.
    public var lang: String
    public var place = ""
    public var deck = ""
    /// 1…99, what the server takes in one add.
    public var copies = 1 { didSet { copies = min(99, max(1, copies)) } }

    /// `proxy` is remembered from the last add; `place`/`deck` are the last place used.
    public init(_ printing: Printing, proxy: Bool = false, lang: String? = nil) {
        self.printing = printing
        self.proxy = proxy
        self.lang = lang ?? printing.lang
        foil = !printing.hasNonfoil
    }

    /// Foil or not, as far as this printing was made that way.
    public mutating func setFoil(_ on: Bool) {
        foil = on ? printing.hasFoil : !printing.hasNonfoil
    }

    /// Another printing ("Other Printing", or the same one in the chosen language). The foil choice
    /// changes only when the new one isn't made that way.
    public mutating func pick(_ other: Printing) {
        printing = other
        lang = other.lang
        setFoil(foil)
    }

    /// The `collection.add` payload, like the PWA's: the printing's facts (`entryFacts()`), then kind,
    /// finish, language, copies and place. `id` is the new entry's.
    public func payload(id: String = String(PendingOp.newID().prefix(12))) -> JSONValue {
        func optional(_ value: String?) -> JSONValue { value.map(JSONValue.string) ?? .null }
        let entry: [String: JSONValue] = [
            "id": .string(id), "name": .string(printing.name), "scryfall_id": .string(printing.id), "set": .string(printing.set),
            "set_name": .string(printing.setName), "collector_number": .string(printing.collectorNumber),
            "image": optional(printing.image?.absoluteString), "image_back": optional(printing.imageBack?.absoluteString),
            "price_eur": optional(printing.price("eur", foil: foil)), "price_usd": optional(printing.price("usd", foil: foil)),
            "proxy": .bool(proxy), "foil": .bool(foil), "lang": .string(lang), "qty": .int(copies),
            "place": .string(deck.isEmpty ? place : ""), "place_deck": .string(deck),
        ]
        return .object(["entry": .object(entry)])
    }
}
