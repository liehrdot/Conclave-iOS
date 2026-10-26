import Foundation

/// What the Collection tab shows: the entries grouped by card, searched and filtered, and the totals on top.
/// Mirrors `groups()`, `matches()` and the summary in the PWA's `collection.js`.
public struct CollectionGroup: Equatable, Sendable, Identifiable {
    public var id: String { name }
    public let name: String
    /// The card's entries: one per printing and place.
    public let entries: [CollectionEntry]

    /// All copies of the card, over every entry.
    public var copies: Int { entries.reduce(0) { $0 + $1.qty } }
}

/// The Collection tab's filter chips (`FILTERS` in `collection.js`).
public enum CollectionFilter: String, CaseIterable, Sendable {
    case all, original, proxy, foil

    func matches(_ entry: CollectionEntry) -> Bool {
        switch self {
        case .all: true
        case .original: !entry.proxy
        case .proxy: entry.proxy
        case .foil: entry.foil
        }
    }
}

/// The numbers above the list.
public struct CollectionTotals: Equatable, Sendable {
    public var cards = 0
    public var proxies = 0
    public var foils = 0
    /// What the original copies cost when they were added, in euros (proxies count nothing).
    public var value: Decimal = 0

    public var originals: Int { cards - proxies }
}

extension ReadModel {
    /// The cards that match the search and the filter, by name as the server sorted them. The search
    /// looks at the name, the set code's start and the place, ignoring case.
    public func collectionGroups(matching query: String = "", filter: CollectionFilter = .all) -> [CollectionGroup] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var order: [String] = []
        var byName: [String: [CollectionEntry]] = [:]
        for entry in collection where filter.matches(entry) {
            if !q.isEmpty, !entry.name.lowercased().contains(q), !(entry.set ?? "").lowercased().hasPrefix(q),
               !placeName(of: entry).lowercased().contains(q) { continue }
            if byName[entry.name] == nil { order.append(entry.name) }
            byName[entry.name, default: []].append(entry)
        }
        return order.map { CollectionGroup(name: $0, entries: byName[$0] ?? []) }
    }

    public var collectionTotals: CollectionTotals {
        var totals = CollectionTotals()
        for entry in collection {
            totals.cards += entry.qty
            if entry.proxy { totals.proxies += entry.qty }
            if entry.foil { totals.foils += entry.qty }
            if !entry.proxy, let price = entry.priceEur.flatMap({ Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX")) }) {
                totals.value += price * Decimal(entry.qty)
            }
        }
        return totals
    }

    /// Where the copies are, as the person reads it: the deck's name, else the free text, else "".
    /// Mirrors `placeName()` in the PWA's `scan.js`.
    public func placeName(of entry: CollectionEntry) -> String {
        if let slug = entry.placeDeck, !slug.isEmpty { return decks.first { $0.slug == slug }?.name ?? slug }
        return entry.place ?? ""
    }

    /// The free-text places in use ("Binder", "Bulk"), most cards first, each once whatever its case.
    /// Mirrors `knownPlaces()` in `scan.js`.
    public var knownPlaces: [(place: String, cards: Int)] {
        var order: [String] = []
        var found: [String: (place: String, cards: Int)] = [:]
        for entry in collection where entry.placeDeck?.isEmpty ?? true {
            let text = (entry.place ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let key = text.lowercased()
            if found[key] == nil { order.append(key) }
            found[key, default: (text, 0)].cards += entry.qty
        }
        return order.compactMap { found[$0] }.enumerated().sorted { a, b in
            (b.element.cards, a.element.place, a.offset) < (a.element.cards, b.element.place, b.offset)
        }.map(\.element)
    }
}

/// Changes to collection entries from the Collection tab, as `collection.update` payloads. Each one
/// carries `prev` (or `restore` for a removed entry), so "Undo" can send the old state back
/// (`Outbox.inverse`). Mirrors `entrySheet()` in the PWA's `collection.js` and `placePage()` in `scan.js`.
public enum CollectionEdit {
    /// The server keeps at most this many copies in one entry.
    public static let maxCopies = 9999

    /// A new number of copies; nil when it didn't change. 0 removes the entry: use `remove` for that.
    public static func quantity(_ entry: CollectionEntry, to qty: Int) -> JSONValue? {
        let qty = min(maxCopies, max(1, qty))
        guard qty != entry.qty else { return nil }
        return .object(["id": .string(entry.id), "qty": .int(qty), "prev": .object(["qty": .int(entry.qty)])])
    }

    /// The entry goes, with everything needed to add it back (`restore`).
    public static func remove(_ entry: CollectionEntry) -> JSONValue {
        .object(["id": .string(entry.id), "qty": .int(0), "restore": .object(restore(entry))])
    }

    /// Original ↔ proxy.
    public static func proxy(_ entry: CollectionEntry, _ on: Bool) -> JSONValue? {
        guard on != entry.proxy else { return nil }
        return .object(["id": .string(entry.id), "proxy": .bool(on), "prev": .object(["proxy": .bool(entry.proxy)])])
    }

    public static func foil(_ entry: CollectionEntry, _ on: Bool) -> JSONValue? {
        guard on != entry.foil else { return nil }
        return .object(["id": .string(entry.id), "foil": .bool(on), "prev": .object(["foil": .bool(entry.foil)])])
    }

    /// Where the copies go. Pick a deck by its slug, or a free text; both empty means no place. Text is
    /// tidied like the server does it (`appops._place`), and a typed deck name means that deck. nil when
    /// nothing changes.
    public static func move(_ entry: CollectionEntry, place: String = "", deck: String = "", decks: [Deck] = []) -> JSONValue? {
        var text = String(place.split(whereSeparator: \.isWhitespace).joined(separator: " ").prefix(80))
        var slug = deck
        if slug.isEmpty, let named = decks.first(where: { $0.name.lowercased() == text.lowercased() }) {
            slug = named.slug
        }
        if !slug.isEmpty { text = "" }
        let before = (place: entry.placeDeck?.isEmpty ?? true ? entry.place ?? "" : "", deck: entry.placeDeck ?? "")
        guard text != before.place || slug != before.deck else { return nil }
        return .object(["id": .string(entry.id), "place": .string(text), "place_deck": .string(slug),
                        "prev": .object(["place": .string(entry.place ?? ""), "place_deck": .string(entry.placeDeck ?? "")])])
    }

    /// The entry as `collection.add` takes it, for the undo of a removal.
    static func restore(_ entry: CollectionEntry) -> [String: JSONValue] {
        func optional(_ value: String?) -> JSONValue { value.map(JSONValue.string) ?? .null }
        var fields: [String: JSONValue] = [
            "id": .string(entry.id), "name": .string(entry.name), "qty": .int(entry.qty), "proxy": .bool(entry.proxy),
            "foil": .bool(entry.foil), "lang": .string(entry.lang), "set": optional(entry.set), "set_name": optional(entry.setName),
            "collector_number": optional(entry.collectorNumber), "scryfall_id": optional(entry.scryfallId),
            "price_eur": optional(entry.priceEur), "place": .string(entry.place ?? ""), "place_deck": .string(entry.placeDeck ?? ""),
        ]
        if let image = entry.image { fields["image"] = .string(image.absoluteString) }
        return fields
    }
}
