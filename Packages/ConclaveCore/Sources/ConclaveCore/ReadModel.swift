import Foundation

/// The parts of the read model (`GET /api/app/data`, Conclave's `appdata.snapshot`) the screens show,
/// typed. Keys the app doesn't know are skipped, and keys that can be missing or null are optional,
/// so a newer PC adding fields never breaks an older app. Texts the PC writes (Rule 0, labels) stay as
/// they come; the server sends them in German and, since Conclave fb16f72, in English too (`*_en`):
/// the `shown…` properties pick the English one and fall back to German for an older server.
/// Field by field: docs/app-api.md in Conclave.
public struct ReadModel: Decodable, Equatable, Sendable {
    public var decks: [Deck]
    public var opponents: [Opponent]
    public var games: [Game]
    public var players: [String]
    /// The quick-pick lists with German labels, and the same in English (nil from an older server).
    public var options: Options
    public var optionsEn: Options?
    /// The collection, one entry per printing and place (`appdata.collection`), sorted by name.
    public var collection: [CollectionEntry]

    /// The labels the app shows: English when the server sends them.
    public var shownOptions: Options { optionsEn ?? options }

    public init(decks: [Deck] = [], opponents: [Opponent] = [], games: [Game] = [], players: [String] = [],
                options: Options = Options(), optionsEn: Options? = nil, collection: [CollectionEntry] = []) {
        self.decks = decks
        self.opponents = opponents
        self.games = games
        self.players = players
        self.options = options
        self.optionsEn = optionsEn
        self.collection = collection
    }

    /// Decodes the server's JSON (snake_case keys). Call it off the main thread: a big account is
    /// several hundred KB.
    public static func decode(_ data: Data) throws -> ReadModel {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(ReadModel.self, from: data)
    }

    /// The same from JSON already read, e.g. what `Optimistic.apply` made.
    public static func decode(_ json: JSONValue) throws -> ReadModel {
        try decode(JSONEncoder().encode(json))
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        decks = try c.decodeIfPresent([Deck].self, forKey: .decks) ?? []
        opponents = try c.decodeIfPresent([Opponent].self, forKey: .opponents) ?? []
        games = try c.decodeIfPresent([Game].self, forKey: .games) ?? []
        players = try c.decodeIfPresent([String].self, forKey: .players) ?? []
        options = try c.decodeIfPresent(Options.self, forKey: .options) ?? Options()
        optionsEn = try c.decodeIfPresent(Options.self, forKey: .optionsEn)
        collection = try c.decodeIfPresent([CollectionEntry].self, forKey: .collection) ?? []
    }

    enum CodingKeys: String, CodingKey { case decks, opponents, games, players, options, optionsEn, collection }

    /// The games played with a deck, newest first (the read model's order).
    public func games(of deck: Deck) -> [Game] { games.filter { $0.deck == deck.slug } }
}

/// The quick-pick lists (`appdata.snapshot` `options`): each a list of key and label, in the order to show.
public struct Options: Decodable, Equatable, Sendable {
    public struct Choice: Equatable, Sendable, Hashable, Identifiable {
        public var id: String { key }
        public var key: String
        public var label: String
    }

    /// Game results ("win", "loss", "draw").
    public var results: [String: String] = [:]
    /// What went wrong in a game (`games.ISSUES`).
    public var issues: [Choice] = []
    /// What an opponent's deck does (`opponents.TAGS`).
    public var tags: [Choice] = []
    /// How a game was decided (`games.HOW`).
    public var how: [Choice] = []

    public init() {}

    /// The label for a key, or the key itself when the list doesn't know it.
    public static func label(_ key: String, in choices: [Choice]) -> String {
        choices.first { $0.key == key }?.label ?? key
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        results = try c.decodeIfPresent([String: String].self, forKey: .results) ?? [:]
        // the server sends [key, label] pairs; a pair of any other shape is skipped
        func pairs(_ key: CodingKeys) throws -> [Choice] {
            (try c.decodeIfPresent([[String]].self, forKey: key) ?? []).compactMap {
                $0.count == 2 ? Choice(key: $0[0], label: $0[1]) : nil
            }
        }
        issues = try pairs(.issues)
        tags = try pairs(.tags)
        how = try pairs(.how)
    }

    enum CodingKeys: String, CodingKey { case results, issues, tags, how }
}

/// Wins, losses and draws, the same for a deck and an opponent.
public struct Record: Decodable, Equatable, Sendable {
    public var games = 0
    public var wins = 0
    public var losses = 0
    public var draws = 0
    /// ISO 8601 time of the last game; nil when there was none.
    public var last: String?

    public init(games: Int = 0, wins: Int = 0, losses: Int = 0, draws: Int = 0, last: String? = nil) {
        self.games = games
        self.wins = wins
        self.losses = losses
        self.draws = draws
        self.last = last
    }
}

public struct Deck: Decodable, Equatable, Sendable, Identifiable {
    public var id: String { slug }
    public var slug: String
    public var name: String
    public var commanders: [String]
    /// Colour identity as letters, `"WUBRG"` order as the PC writes it; "" for colourless.
    public var colors: String
    public var bracket: Int?
    /// "low" | "mid" | "high" inside the bracket.
    public var tier: String?
    /// The bracket and tier in German ("oberes Bracket 3") and English ("upper Bracket 3").
    public var level: String?
    public var levelEn: String?
    public var proxy: Bool
    /// nil when the PC hasn't checked the deck yet.
    public var legal: Bool?
    public var description: String?
    public var version: Int?
    public var updated: String?
    /// The PC hasn't checked the newest version yet (it was changed on a phone).
    public var checking: Bool
    public var rule0: Rule0
    /// Rule 0 in English: the same rows and flags (nil from an older server).
    public var rule0En: Rule0?
    public var speed: Speed?
    public var cards: [Card]
    public var maybe: [Card]
    public var record: Record
    public var pinned: Bool
    public var shelved: Bool

    /// Only the slug and name must be there: a key an older server (or the web app's demo) doesn't write yet
    /// gets its empty value, so one missing flag never hides every deck.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        slug = try c.decode(String.self, forKey: .slug)
        name = try c.decode(String.self, forKey: .name)
        commanders = try c.decodeIfPresent([String].self, forKey: .commanders) ?? []
        colors = try c.decodeIfPresent(String.self, forKey: .colors) ?? ""
        bracket = try c.decodeIfPresent(Int.self, forKey: .bracket)
        tier = try c.decodeIfPresent(String.self, forKey: .tier)
        level = try c.decodeIfPresent(String.self, forKey: .level)
        levelEn = try c.decodeIfPresent(String.self, forKey: .levelEn)
        proxy = try c.decodeIfPresent(Bool.self, forKey: .proxy) ?? false
        legal = try c.decodeIfPresent(Bool.self, forKey: .legal)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        version = try c.decodeIfPresent(Int.self, forKey: .version)
        updated = try c.decodeIfPresent(String.self, forKey: .updated)
        checking = try c.decodeIfPresent(Bool.self, forKey: .checking) ?? false
        rule0 = try c.decodeIfPresent(Rule0.self, forKey: .rule0) ?? Rule0(rows: [], text: "")
        rule0En = try c.decodeIfPresent(Rule0.self, forKey: .rule0En)
        speed = try c.decodeIfPresent(Speed.self, forKey: .speed)
        cards = try c.decodeIfPresent([Card].self, forKey: .cards) ?? []
        maybe = try c.decodeIfPresent([Card].self, forKey: .maybe) ?? []
        record = try c.decodeIfPresent(Record.self, forKey: .record) ?? Record()
        pinned = try c.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
        shelved = try c.decodeIfPresent(Bool.self, forKey: .shelved) ?? false
    }

    enum CodingKeys: String, CodingKey {
        case slug, name, commanders, colors, bracket, tier, level, levelEn, proxy, legal, description, version, updated
        case checking, rule0, rule0En, speed, cards, maybe, record, pinned, shelved
    }

    public struct Card: Decodable, Equatable, Sendable, Hashable {
        public var name: String
        public var qty: Int?
        /// English category key (`Ramp`, `Draw`, …); "" when none.
        public var category: String?
    }

    /// Rule 0: what the table should know before a game, written by the PC.
    public struct Rule0: Decodable, Equatable, Sendable {
        public var rows: [Row]
        /// The same as one copyable text.
        public var text: String

        public struct Row: Decodable, Equatable, Sendable, Hashable {
            public var label: String
            public var value: String
            /// Worth mentioning at the table (a game changer, a combo, …).
            public var flag: Bool
        }
    }

    /// The deck's tempo from its total mana value (Conclave's `speed.rate`).
    public struct Speed: Decodable, Equatable, Sendable {
        public var total: Double?
        public var effective: Double?
        public var key: String?
        public var label: String?
        public var text: String?
        public var labelEn: String?
        public var textEn: String?

        /// The tempo's name and what it means, in English when the server sends it.
        public var shownLabel: String? { labelEn ?? label }
        public var shownText: String? { textEn ?? text }
    }

    /// What the app shows: English when the server sends it, else the German.
    public var shownRule0: Rule0 { rule0En ?? rule0 }
    public var shownLevel: String? { levelEn ?? level }

    /// Cards in the deck, commanders not counted twice.
    public var cardCount: Int { cards.reduce(0) { $0 + ($1.qty ?? 1) } }
}

public struct Opponent: Decodable, Equatable, Sendable, Identifiable {
    public var id: String
    /// What to call it: the label, else the commanders.
    public var title: String
    public var label: String?
    public var player: String?
    public var commanders: [String]
    public var colors: String?
    public var bracket: Int?
    /// Keys of Conclave's `opponents.TAGS` ("combo", "stax", …).
    public var tags: [String]
    /// Newest first.
    public var notes: [Note]
    public var record: OpponentRecord

    public struct Note: Decodable, Equatable, Sendable, Identifiable {
        public var id: String
        public var text: String
        public var at: String?
        public var gameId: String?
        public var deckSlug: String?
    }

    public struct OpponentRecord: Decodable, Equatable, Sendable {
        public var games = 0
        public var wins = 0
        public var losses = 0
        public var draws = 0
        public var last: String?
        /// How each of the person's decks did against this one.
        public var perDeck: [PerDeck] = []

        public struct PerDeck: Decodable, Equatable, Sendable {
            public var slug: String?
            public var name: String
            public var games: Int
            public var wins: Int
            public var losses: Int
        }
    }
}

public struct Game: Decodable, Equatable, Sendable, Identifiable {
    public var id: String
    /// The deck's slug.
    public var deck: String
    public var played: String?
    /// "win" | "loss" | "draw".
    public var result: String
    /// The opponents' commanders, as shown.
    public var opponents: [String]
    public var opponentIds: [String?]?
    public var turn: Int?
    public var note: String?
    /// Finishing place 1…N, when it was recorded.
    public var place: Int?
}

extension ReadModel {
    /// The server's times (`2026-10-02T20:00:00+00:00`, sometimes with fractions) as dates.
    public static func date(_ text: String?) -> Date? {
        guard let text, !text.isEmpty else { return nil }
        if let date = try? Date(text, strategy: .iso8601) { return date }
        return try? Date(text, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true))
    }
}
