import Foundation

/// The Cards tab's filters: what a card does (a Tagger role, like the iPad builder's chips in the PWA's
/// `build.js` `FILTERS`), its colours and its card types. With any filter set, the name search becomes a
/// Scryfall search, and with no name it lists the most played cards that fit.
public struct CardFilter: Equatable, Sendable {
    public struct Role: Equatable, Sendable, Identifiable {
        public var id: String { key }
        /// Scryfall syntax, an Oracle tag.
        public let key: String
        public let label: String
    }

    public static let roles = [
        Role(key: "otag:ramp", label: "Ramp"), Role(key: "otag:draw", label: "Card Draw"),
        Role(key: "otag:removal", label: "Removal"), Role(key: "otag:sweeper", label: "Board Wipes"),
        Role(key: "otag:counterspell", label: "Counterspells"), Role(key: "otag:tutor", label: "Tutors"),
    ]

    /// One of `roles`' keys.
    public var role: String?
    /// From `DescribeFilter.colors`: W U B R G, and C for colourless.
    public var colors: [String] = []
    /// From `DescribeFilter.types`.
    public var types: [String] = []

    public init(role: String? = nil, colors: [String] = [], types: [String] = []) {
        self.role = role
        self.colors = colors
        self.types = types
    }

    public var isEmpty: Bool { role == nil && colors.isEmpty && types.isEmpty }

    /// The Scryfall search for a typed name with these filters; nil without any filter (then the plain
    /// name search runs).
    public func query(name: String) -> String? {
        guard !isEmpty else { return nil }
        let typed = name.trimmingCharacters(in: .whitespaces)
        return Self.compose(([typed, role ?? ""]).filter { !$0.isEmpty }.joined(separator: " "), colors: colors, types: types)
    }

    /// A query plus colour identity, types and Commander legality, the way the sync server finishes a
    /// described search (`compose()` in Conclave's `cardsearch.py`): within the picked colours and at least
    /// one of them, colourless cards only when C is picked too (C alone = colourless only); several types
    /// = any of them.
    public static func compose(_ query: String, colors: [String] = [], types: [String] = []) -> String {
        var parts = query.isEmpty ? [] : [query.lowercased().contains(" or ") ? "(\(query))" : query]
        let picked = DescribeFilter.colors.dropLast().filter { colors.contains($0) }
        let colorless = colors.contains("C")
        if !picked.isEmpty {
            parts.append("id<=\(picked.joined().lowercased())" + (colorless ? "" : " -id:c"))
        } else if colorless {
            parts.append("id:c")
        }
        let kinds = DescribeFilter.types.filter { types.contains($0) }
        if kinds.count == 1 {
            parts.append("t:\(kinds[0])")
        } else if !kinds.isEmpty {
            parts.append("(" + kinds.map { "t:\($0)" }.joined(separator: " OR ") + ")")
        }
        parts.append("f:commander")
        return parts.joined(separator: " ")
    }
}
