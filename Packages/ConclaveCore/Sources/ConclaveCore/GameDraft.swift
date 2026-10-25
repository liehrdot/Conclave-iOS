import Foundation

/// A game while the person fills in the "Log a Game" screen, and the `game.add` it turns into.
/// Mirrors the game sheet in the PWA's `forms.js` (`freshGame()`, `setPlace()`, `saveGame()`).
public struct GameDraft: Equatable, Sendable {
    /// One opponent at the table: a known opponent deck, or a commander typed in (the server then makes
    /// a new opponent deck, or links the newest one with that commander).
    public struct Seat: Equatable, Sendable, Identifiable {
        public let id: String
        /// The known opponent deck, nil for a typed commander.
        public var opponentID: String?
        public var commander: String
        public var colors: String
        public var place: Int?

        public init(opponentID: String? = nil, commander: String, colors: String = "", place: Int? = nil) {
            id = PendingOp.newID()
            self.opponentID = opponentID
            self.commander = commander
            self.colors = colors
            self.place = place
        }
    }

    /// Within this time the last game's opponents sit at the table again (the PWA's `REMATCH_HOURS`).
    public static let rematchHours: Double = 8
    /// The most opponents a game takes (`appops`: five).
    public static let maxOpponents = 5

    public let id: String
    public var deck: String
    /// "win" | "loss" | "draw"; nil until picked, and a game can't be saved without it.
    public private(set) var result: String?
    /// The person's own finishing place.
    public private(set) var place: Int?
    public private(set) var seats: [Seat]
    /// The last game's opponents were taken over (shown as "Same table as last game").
    public private(set) var rematch: Bool
    public var turn: Int?
    /// Keys of the read model's `options.issues`, only kept for a loss or a draw.
    public var issues: [String] = []
    /// A key of `options.how`.
    public var how: String?
    public var note = ""

    /// A new game with `deck`; when the last game is less than `rematchHours` old, its opponents again.
    public init(deck: String, library: ReadModel, now: Date = .now) {
        id = PendingOp.newID()
        self.deck = deck
        var seats: [Seat] = []
        if let last = library.games.first, let played = ReadModel.date(last.played),
           now.timeIntervalSince(played) < Self.rematchHours * 3600 {
            for (index, name) in last.opponents.enumerated() {
                let known = (last.opponentIds?.indices.contains(index) == true ? last.opponentIds?[index] : nil)
                    .flatMap { id in library.opponents.first { $0.id == id } }
                seats.append(Seat(opponentID: known?.id, commander: name, colors: known?.colors ?? ""))
            }
        }
        self.seats = Array(seats.prefix(Self.maxOpponents))
        rematch = !self.seats.isEmpty
    }

    /// Everyone at the table: the person plus the opponents (places go up to this, at most 6).
    public var tableSize: Int { min(6, 1 + seats.count) }
    public var canSave: Bool { result != nil }

    /// Picks the result. A win is first place, a loss can't be.
    public mutating func setResult(_ result: String) {
        self.result = result
        if result == "win", place == nil, !seats.isEmpty { place = 1 }
        if result == "loss", place == 1 { place = nil }
    }

    /// Sets a player's place (`seat` nil = the person); the same place again clears it. When all but one
    /// player have different places, the last one gets the place that is left. The person's place decides
    /// a win or a loss.
    public mutating func setPlace(_ newPlace: Int, seat: Int? = nil) {
        let current = seat.map { seats[$0].place } ?? place
        setPlace(of: seat, current == newPlace ? nil : newPlace)
        let everyone: [Int?] = [nil] + seats.indices.map { $0 }
        let open = everyone.filter { placeOf($0) == nil }
        let taken = Set(everyone.compactMap(placeOf))
        if placeOf(seat) != nil, open.count == 1, taken.count == everyone.count - 1,
           let left = (1...everyone.count).first(where: { !taken.contains($0) }) {
            setPlace(of: open[0], left)
        }
        if place == 1 { result = "win" } else if place != nil, result != "draw" { result = "loss" }
    }

    public func placeOf(_ seat: Int?) -> Int? { seat.map { seats[$0].place } ?? place }

    private mutating func setPlace(of seat: Int?, _ value: Int?) {
        if let seat { seats[seat].place = value } else { place = value }
    }

    /// Adds a known opponent deck, or a typed commander (`opponentID` nil). Nothing past `maxOpponents`.
    public mutating func add(_ seat: Seat) {
        guard seats.count < Self.maxOpponents else { return }
        if let id = seat.opponentID, seats.contains(where: { $0.opponentID == id }) { return }
        seats.append(seat)
        rematch = false
    }

    public mutating func removeSeat(at index: Int) {
        seats.remove(at: index)
        rematch = false
        // places that no longer fit the smaller table go (the PWA's `fitPlaces()`)
        if let place, place > tableSize { self.place = nil }
        for i in seats.indices where (seats[i].place ?? 0) > tableSize { seats[i].place = nil }
    }

    /// The `game.add` payload, like `saveGame()`; nil without a result.
    public var payload: JSONValue? {
        guard let result else { return nil }
        var game: [String: JSONValue] = [
            "id": .string(id), "deck": .string(deck), "result": .string(result),
            "turn": turn.map(JSONValue.int) ?? .null,
            "issues": .array((result == "win" ? [] : issues).map(JSONValue.string)),
            "how": how.map(JSONValue.string) ?? .null,
            "note": .string(note.trimmingCharacters(in: .whitespacesAndNewlines)),
        ]
        if let place, place <= tableSize { game["place"] = .int(place) }
        let opponents: [JSONValue] = seats.map { seat in
            .object([
                "id": seat.opponentID.map(JSONValue.string) ?? .null,
                "commander": .string(seat.commander),
                "colors": .string(seat.colors),
                "new_id": seat.opponentID == nil ? .string(String(seat.id.prefix(8))) : .null,
                "place": seat.place.map(JSONValue.int) ?? .null,
            ])
        }
        return .object(["game": .object(game), "opponents": .array(opponents)])
    }
}
