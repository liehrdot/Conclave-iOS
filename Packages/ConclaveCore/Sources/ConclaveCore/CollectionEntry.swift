import Foundation

/// One collection entry of the read model (`appdata.collection`, Conclave's `COLLECTION_KEYS`): copies
/// of one printing in one place. `placeDeck` set means the copies lie in that deck: they are the deck's
/// own cards, the printing the PC shows in the deck list.
public struct CollectionEntry: Decodable, Equatable, Sendable, Identifiable, Hashable {
    public var id: String
    public var name: String
    public var qty: Int
    public var proxy: Bool
    public var foil: Bool
    /// Scryfall's language code ("en", "de", "ja", …).
    public var lang: String
    public var set: String?
    public var setName: String?
    public var collectorNumber: String?
    public var scryfallId: String?
    /// The price when it was added, in euros, as the PC wrote it ("8.22").
    public var priceEur: String?
    /// Where the copies are: free text ("Binder", "Bulk") or a deck's slug.
    public var place: String?
    public var placeDeck: String?
    /// Only for entries without a Scryfall id (the read model leaves derivable URLs out).
    public var image: URL?

    public init(id: String, name: String, qty: Int = 1, proxy: Bool = false, foil: Bool = false, lang: String = "en",
                set: String? = nil, setName: String? = nil, collectorNumber: String? = nil, scryfallId: String? = nil,
                priceEur: String? = nil, place: String? = nil, placeDeck: String? = nil, image: URL? = nil) {
        self.id = id
        self.name = name
        self.qty = qty
        self.proxy = proxy
        self.foil = foil
        self.lang = lang
        self.set = set
        self.setName = setName
        self.collectorNumber = collectorNumber
        self.scryfallId = scryfallId
        self.priceEur = priceEur
        self.place = place
        self.placeDeck = placeDeck
        self.image = image
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        qty = try c.decodeIfPresent(Int.self, forKey: .qty) ?? 1
        proxy = try c.decodeIfPresent(Bool.self, forKey: .proxy) ?? false
        foil = try c.decodeIfPresent(Bool.self, forKey: .foil) ?? false
        lang = try c.decodeIfPresent(String.self, forKey: .lang) ?? "en"
        set = try c.decodeIfPresent(String.self, forKey: .set)
        setName = try c.decodeIfPresent(String.self, forKey: .setName)
        collectorNumber = try c.decodeIfPresent(String.self, forKey: .collectorNumber)
        scryfallId = try c.decodeIfPresent(String.self, forKey: .scryfallId)
        priceEur = try? c.decodeIfPresent(String.self, forKey: .priceEur)
        place = try c.decodeIfPresent(String.self, forKey: .place)
        placeDeck = try c.decodeIfPresent(String.self, forKey: .placeDeck)
        image = (try? c.decodeIfPresent(String.self, forKey: .image)).flatMap { $0.flatMap(URL.init(string:)) }
    }

    enum CodingKeys: String, CodingKey {
        case id, name, qty, proxy, foil, lang, set, setName, collectorNumber, scryfallId, priceEur, place, placeDeck, image
    }

    public enum ImageSize: String, Sendable { case small, normal, large }

    /// This printing's picture on Scryfall's image CDN, from its id; the back for a double-faced card.
    /// Mirrors `entryImage()` in the PWA's `scry.js`. Falls back to the stored URL (front only).
    public func imageURL(_ size: ImageSize = .normal, back: Bool = false) -> URL? {
        guard let id = scryfallId?.lowercased(), id.count == 36,
              id.allSatisfy({ $0.isHexDigit || $0 == "-" }) else { return back ? nil : image }
        let a = id.prefix(1), b = id.dropFirst().prefix(1)
        return URL(string: "https://cards.scryfall.io/\(size.rawValue)/\(back ? "back" : "front")/\(a)/\(b)/\(id).jpg")
    }

    /// "Marvel Super Heroes Commander · #170", what the PC shows for a printing.
    public var printing: String? {
        let set = setName ?? set?.uppercased()
        switch (set, collectorNumber) {
        case let (set?, number?): return "\(set) · #\(number)"
        case let (set?, nil): return set
        case let (nil, number?): return "#\(number)"
        default: return nil
        }
    }
}

extension ReadModel {
    /// The person's own copies of a card that lie in a deck: real copies before proxies (foils first
    /// among each), at most as many as the deck plays. Mirrors `_deck_value()` in Conclave's
    /// `collection.py`, the copies the PC's deck list shows.
    public func copies(of card: String, in deck: Deck) -> [CollectionEntry] {
        let needed = deck.cards.first { Self.sameCard($0.name, card) }?.qty ?? 1
        let placed = collection.filter { $0.placeDeck == deck.slug && $0.qty > 0 && Self.sameCard($0.name, card) }
        var left = needed
        var out: [CollectionEntry] = []
        let order = placed.enumerated().sorted { a, b in
            (a.element.proxy ? 1 : 0, a.element.foil ? 0 : 1, a.offset) < (b.element.proxy ? 1 : 0, b.element.foil ? 0 : 1, b.offset)
        }
        for entry in order.map(\.element) where left > 0 {
            var entry = entry
            entry.qty = min(entry.qty, left)
            left -= entry.qty
            out.append(entry)
        }
        return out
    }

    /// The same card by name: equal, or one of them is the other's front face ("Fable of the
    /// Mirror-Breaker" and "Fable of the Mirror-Breaker // Reflection of Kiki-Jiki"), ignoring case.
    public static func sameCard(_ a: String, _ b: String) -> Bool {
        func front(_ name: String) -> String { name.components(separatedBy: " // ")[0].lowercased() }
        return a.lowercased() == b.lowercased() || front(a) == front(b)
    }
}
