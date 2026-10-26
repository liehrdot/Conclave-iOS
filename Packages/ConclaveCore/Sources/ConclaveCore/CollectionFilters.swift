import Foundation

/// The Collection tab's "Filters" sheet: where the copies are, the card's colours and types, the set, the
/// language and what one copy is worth. Within one kind any picked choice matches; the kinds together all
/// have to match. Colours and types need the card's Scryfall data (`card`), the rest is in the entry.
/// The web app has only the Alle/Original/Proxy/Foil chips; these go further.
public struct CollectionFilters: Equatable, Codable, Sendable {
    /// `deck:<slug>`, `place:<text, lowercased>`, `none` (no place) or `free` (not placed in a deck).
    public var places: Set<String> = []
    /// Colour identity letters W U B R G, and C: a card fits when its colours are all picked, like the Cards
    /// tab (`id<=`); colourless cards only with C.
    public var colors: Set<String> = []
    /// `DescribeFilter.types`: the front face's type line has one of them.
    public var types: Set<String> = []
    /// Set codes, lowercased.
    public var sets: Set<String> = []
    /// Scryfall language codes ("en", "de").
    public var languages: Set<String> = []
    /// One copy is worth at least this many euros (the price when it was added); proxies never are.
    public var minValue: Int?

    public init() {}

    public static let values = [1, 5, 20]

    public var isEmpty: Bool { self == CollectionFilters() }

    /// Whether the filters need the cards' Scryfall data.
    public var needsCards: Bool { !colors.isEmpty || !types.isEmpty }

    /// The place key of an entry, as `places` holds it.
    public static func placeKey(_ entry: CollectionEntry) -> String {
        if let deck = entry.placeDeck, !deck.isEmpty { return "deck:\(deck)" }
        let text = (entry.place ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return text.isEmpty ? "none" : "place:\(text)"
    }

    public func matches(_ entry: CollectionEntry, card: Card?) -> Bool {
        if !places.isEmpty {
            let key = Self.placeKey(entry)
            guard places.contains(key) || (places.contains("free") && !key.hasPrefix("deck:")) else { return false }
        }
        if !sets.isEmpty, !sets.contains((entry.set ?? "").lowercased()) { return false }
        if !languages.isEmpty, !languages.contains(entry.lang) { return false }
        if let minValue {
            guard !entry.proxy, let price = entry.priceValue, price >= Decimal(minValue) else { return false }
        }
        if !colors.isEmpty {
            guard let card else { return false }
            let identity = Set(card.colors.map(String.init))
            guard identity.isEmpty ? colors.contains("C") : identity.isSubset(of: colors) else { return false }
        }
        if !types.isEmpty {
            guard let line = card?.faces.first?.typeLine.lowercased(), types.contains(where: line.contains) else { return false }
        }
        return true
    }

    /// The filters in a few words for the row above the list: "Green or Black · Creature · in Binder".
    public func summary(decks: [Deck], places known: [(place: String, cards: Int)] = []) -> String {
        var parts: [String] = []
        let names = Dictionary(zip(DescribeFilter.colors, ["White", "Blue", "Black", "Red", "Green", "Colorless"]), uniquingKeysWith: { a, _ in a })
        let colors = DescribeFilter.colors.filter(self.colors.contains).compactMap { names[$0] }
        if !colors.isEmpty { parts.append(colors.formatted(.list(type: .or))) }
        let types = DescribeFilter.types.filter(self.types.contains).map(\.capitalized)
        if !types.isEmpty { parts.append(types.formatted(.list(type: .or))) }
        let where_ = places.sorted().map { key -> String in
            switch key {
            case "none": return "no place"
            case "free": return "not in a deck"
            default:
                if key.hasPrefix("deck:") {
                    let slug = String(key.dropFirst(5))
                    return "in " + (decks.first { $0.slug == slug }?.name ?? slug)
                }
                let text = String(key.dropFirst(6))
                return "in " + (known.first { $0.place.lowercased() == text }?.place ?? text)
            }
        }
        if !where_.isEmpty { parts.append(where_.formatted(.list(type: .or))) }
        if !sets.isEmpty { parts.append(sets.sorted().map { $0.uppercased() }.formatted(.list(type: .or))) }
        if !languages.isEmpty {
            parts.append(languages.sorted().map { Locale.current.localizedString(forLanguageCode: $0) ?? $0.uppercased() }.formatted(.list(type: .or)))
        }
        if let minValue { parts.append("over \(minValue) €") }
        return parts.joined(separator: " · ")
    }
}

/// What the Filters sheet offers, from the collection itself.
public struct CollectionChoices: Sendable {
    /// The decks that hold copies.
    public var decks: [Deck]
    /// The free-text places, most cards first.
    public var places: [String]
    /// The sets, by name.
    public var sets: [(code: String, name: String)]
    /// English first.
    public var languages: [String]
}

/// How the Collection tab orders its cards.
public enum CollectionSort: String, CaseIterable, Codable, Sendable {
    case name, value, copies, set

    public var label: String {
        switch self {
        case .name: "Name"
        case .value: "Value"
        case .copies: "Copies"
        case .set: "Set"
        }
    }
}

extension CollectionEntry {
    /// The price of one copy when it was added, as a number.
    public var priceValue: Decimal? { priceEur.flatMap { Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX")) } }
}

extension CollectionGroup {
    /// What the group's original copies are worth together.
    public var value: Decimal {
        entries.reduce(0) { sum, entry in entry.proxy ? sum : sum + (entry.priceValue ?? 0) * Decimal(entry.qty) }
    }
}

extension ReadModel {
    /// The groups with the sheet's filters applied (an entry stays when it matches; a card stays while one of
    /// its entries does) and in the picked order; ties keep the name order.
    public func collectionGroups(matching query: String = "", filter: CollectionFilter = .all, filters: CollectionFilters,
                                 sort: CollectionSort = .name, card: (String) -> Card? = { _ in nil }) -> [CollectionGroup] {
        var groups = collectionGroups(matching: query, filter: filter)
        if !filters.isEmpty {
            groups = groups.compactMap { group in
                let found = filters.needsCards ? card(group.name) : nil
                let kept = group.entries.filter { filters.matches($0, card: found) }
                return kept.isEmpty ? nil : CollectionGroup(name: group.name, entries: kept)
            }
        }
        let ordered = groups.enumerated()
        switch sort {
        case .name:
            return groups
        case .value:
            return ordered.sorted { ($1.element.value, $0.offset) < ($0.element.value, $1.offset) }.map(\.element)
        case .copies:
            return ordered.sorted { ($1.element.copies, $0.offset) < ($0.element.copies, $1.offset) }.map(\.element)
        case .set:
            func set(_ group: CollectionGroup) -> String { group.entries.first?.setName ?? group.entries.first?.set ?? "~" }
            return ordered.sorted { (set($0.element), $0.offset) < (set($1.element), $1.offset) }.map(\.element)
        }
    }

    /// The choices the Filters sheet offers: only what the collection has.
    public var collectionChoices: CollectionChoices {
        let slugs = Set(collection.compactMap { $0.placeDeck }.filter { !$0.isEmpty })
        var sets: [String: String] = [:]
        for entry in collection {
            if let code = entry.set?.lowercased(), !code.isEmpty { sets[code] = entry.setName ?? sets[code] ?? code.uppercased() }
        }
        var languages: [String] = []
        for entry in collection where !languages.contains(entry.lang) { languages.append(entry.lang) }
        return CollectionChoices(
            decks: decks.filter { slugs.contains($0.slug) }, places: knownPlaces.map(\.place),
            sets: sets.map { (code: $0.key, name: $0.value) }.sorted { ($0.name, $0.code) < ($1.name, $1.code) },
            languages: languages.sorted { ($0 == "en" ? 0 : 1, $0) < ($1 == "en" ? 0 : 1, $1) })
    }
}
