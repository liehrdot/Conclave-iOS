import Foundation

/// Shows the phone's own changes before the server has them: applies the outbox's operations to a copy of
/// the read model, the way the server will (`appops.apply`, then `appdata.snapshot`'s records and order).
/// Mirrors `apply()` and `recompute()` in the PWA's `data.js`, checked against Conclave's shared cases
/// (`ops.json`) in `OptimisticTests`.
///
/// It works on the raw JSON, not on `ReadModel`, so keys the app doesn't model survive. Games and opponent
/// decks for now; the other types (decks, collection) leave the model as it is until their screens come.
/// An operation the server would refuse (no result, a deleted deck) is not shown: the server's answer
/// marks it failed, with its reason.
public enum Optimistic {
    typealias Object = [String: JSONValue]

    /// The read model as it will look once the server has applied `ops` (the outbox's pending and sent ones).
    public static func apply(_ ops: [PendingOp], to base: JSONValue) -> JSONValue {
        guard var model = base.object, !ops.isEmpty else { return base }
        for op in ops where op.status != .failed {
            apply(op, to: &model)
        }
        recompute(&model)
        return .object(model)
    }

    static func apply(_ op: PendingOp, to model: inout Object) {
        let p = op.payload
        switch op.type {
        case "game.add":
            addGame(p, op: op, to: &model)
        case "game.delete":
            model["games"] = .array(objects(model["games"]).filter { !($0["id"] == p["id"] && $0["deck"] == p["deck"]) }.map(JSONValue.object))
        case "opponent.add":
            var opponents = objects(model["opponents"])
            guard let fields = p["opponent"]?.object, let id = fields["id"]?.string,
                  !opponents.contains(where: { $0["id"]?.string == id }),
                  var opponent = newOpponent(fields, at: op.at, tags: known(model, "tags")) else { return }
            if let note = text(p["note"]) {
                opponent["notes"] = .array([.object(makeNote(p["note_id"]?.string ?? "\(op.id)-n", note, at: op.at))])
            }
            opponents.append(opponent)
            model["opponents"] = .array(opponents.map(JSONValue.object))
        case "opponent.update", "opponent.note", "opponent.note_delete", "opponent.delete":
            changeOpponent(op, in: &model)
        default:
            break  // decks and the collection: not shown at once yet
        }
    }

    /// `game.add`, like `appops.apply`: links each opponent slot by id, else the newest opponent deck with
    /// that commander, else makes a new one; the slot's note goes to that opponent.
    static func addGame(_ p: JSONValue, op: PendingOp, to model: inout Object) {
        guard var game = p["game"]?.object, let slug = game["deck"]?.string, let id = game["id"]?.string,
              let deck = objects(model["decks"]).first(where: { $0["slug"]?.string == slug }),
              let result = game["result"]?.string, ["win", "loss", "draw"].contains(result) else { return }
        var games = objects(model["games"])
        if games.contains(where: { $0["id"]?.string == id && $0["deck"]?.string == slug }) { return }  // sent twice
        var opponents = objects(model["opponents"])
        var names: [JSONValue] = [], ids: [JSONValue] = [], places: [JSONValue] = []
        for case .object(let slot) in (p["opponents"]?.array ?? []).prefix(5) {
            let commander = text(slot["commander"])
            var index = match(opponents, slot)
            if index == nil, let commander,
               let made = newOpponent(["id": slot["new_id"] ?? .null, "commanders": .array([.string(commander)]), "colors": slot["colors"] ?? .null], at: op.at, tags: known(model, "tags")) {
                opponents.append(made)
                index = opponents.count - 1
            }
            guard let index else { continue }
            if let note = text(slot["note"]) {
                opponents[index]["notes"] = .array([.object(makeNote("\(op.id)-\(opponents[index]["id"]?.string ?? "")", note, at: op.at, game: id, deck: slug))]
                    + (opponents[index]["notes"]?.array ?? []))
            }
            opponents[index]["updated"] = .string(op.at)
            names.append(.string(commander ?? opponents[index]["commanders"]?[0]?.string ?? "?"))
            ids.append(opponents[index]["id"] ?? .null)
            places.append(slot["place"] ?? .null)
        }
        // the fields the server keeps, cleaned the same way
        let turn = game["turn"]?.int.flatMap { (1...60).contains($0) ? $0 : nil }
        game["played"] = game["played"]?.string.map(JSONValue.string) ?? .string(op.at)
        game["opponents"] = .array(names)
        game["turn"] = turn.map(JSONValue.int) ?? .null
        game["issues"] = cleanKeys(game["issues"], known: known(model, "issues"))
        game["mvp"] = text(game["mvp"]).map(JSONValue.string) ?? .null
        game["note"] = .string(text(game["note"]) ?? "")
        game["version"] = deck["version"] ?? .null
        game["opponent_ids"] = ids.isEmpty ? nil : .array(ids)
        if let started = game["started"], started != .string("me"), !(started.int.map { (0..<names.count).contains($0) } ?? false) {
            game["started"] = nil
        }
        let (place, theirs) = cleanPlaces(game["place"], places, opponents: names.count)
        game["place"] = place.map(JSONValue.int)
        game["opponent_places"] = theirs.map { .array($0.map { $0.map(JSONValue.int) ?? .null }) }
        games.insert(game, at: 0)
        model["games"] = .array(games.map(JSONValue.object))
        model["opponents"] = .array(opponents.map(JSONValue.object))
    }

    /// `opponent.update`, `.note`, `.note_delete` and `.delete`; an opponent that is gone changes nothing.
    static func changeOpponent(_ op: PendingOp, in model: inout Object) {
        let p = op.payload
        var opponents = objects(model["opponents"])
        guard let index = opponents.firstIndex(where: { $0["id"] != nil && $0["id"] == p["id"] }) else { return }
        switch op.type {
        case "opponent.update":
            if let commanders = p["commanders"] {
                let names = (commanders.array ?? []).compactMap { text($0) }.prefix(2)
                guard !names.isEmpty else { return }  // the server refuses an opponent without a commander
                if JSONValue.array(names.map(JSONValue.string)) != opponents[index]["commanders"] {
                    opponents[index]["commanders"] = .array(names.map(JSONValue.string))
                    opponents[index]["colors"] = .string(colors(p["colors"]))
                }
            }
            for key in ["player", "label", "bracket"] where p[key] != nil {
                opponents[index][key] = p[key]
            }
            if p["tags"] != nil { opponents[index]["tags"] = cleanKeys(p["tags"], known: known(model, "tags")) }
            opponents[index]["updated"] = .string(op.at)
        case "opponent.note":
            guard let noteID = p["note_id"]?.string, let body = text(p["text"]) else { return }
            let notes = opponents[index]["notes"]?.array ?? []
            if notes.contains(where: { $0["id"]?.string == noteID }) { return }
            opponents[index]["notes"] = .array([.object(makeNote(noteID, body, at: op.at))] + notes)
            opponents[index]["updated"] = .string(op.at)
        case "opponent.note_delete":
            opponents[index]["notes"] = .array((opponents[index]["notes"]?.array ?? []).filter { $0["id"] != p["note_id"] })
        case "opponent.delete":
            opponents.remove(at: index)
        default:
            return
        }
        model["opponents"] = .array(opponents.map(JSONValue.object))
    }

    /// What the server works out from the games: each deck's and opponent's record, the order of games,
    /// decks and opponents, the player names. Mirrors `appdata.snapshot` (and `recompute()` in `data.js`).
    static func recompute(_ model: inout Object) {
        let games = stableSorted(objects(model["games"])) { ($0["played"]?.string ?? "") > ($1["played"]?.string ?? "") }
        model["games"] = .array(games.map(JSONValue.object))

        var decks = objects(model["decks"])
        for i in decks.indices {
            decks[i]["record"] = .object(record(games.filter { $0["deck"] == decks[i]["slug"] }))
        }
        decks = stableSorted(decks) { lastAndUpdated($1).lexicographicallyPrecedes(lastAndUpdated($0)) }
        decks = stableSorted(decks) { rank($0).lexicographicallyPrecedes(rank($1)) }
        model["decks"] = .array(decks.map(JSONValue.object))

        let names = Dictionary(decks.compactMap { d in d["slug"]?.string.map { ($0, d["name"] ?? .string($0)) } }) { first, _ in first }
        var opponents = objects(model["opponents"])
        for i in opponents.indices {
            let mine = games.filter { faced(opponents[i], $0) }
            var perDeck: [Object] = []
            for game in mine {
                let slug = game["deck"]?.string ?? ""
                let result = game["result"]?.string
                if let at = perDeck.firstIndex(where: { $0["slug"]?.string == slug }) {
                    perDeck[at]["games"] = .int((perDeck[at]["games"]?.int ?? 0) + 1)
                    perDeck[at]["wins"] = .int((perDeck[at]["wins"]?.int ?? 0) + (result == "win" ? 1 : 0))
                    perDeck[at]["losses"] = .int((perDeck[at]["losses"]?.int ?? 0) + (result == "loss" ? 1 : 0))
                } else {
                    perDeck.append(["slug": .string(slug), "name": names[slug] ?? .string(slug), "games": .int(1),
                                    "wins": .int(result == "win" ? 1 : 0), "losses": .int(result == "loss" ? 1 : 0)])
                }
            }
            var record = record(mine)
            record["per_deck"] = .array(stableSorted(perDeck) { ($0["games"]?.int ?? 0) > ($1["games"]?.int ?? 0) }.map(JSONValue.object))
            opponents[i]["record"] = .object(record)
            opponents[i]["title"] = .string(title(opponents[i]))
        }
        opponents = stableSorted(opponents) { lastAndUpdated($1).lexicographicallyPrecedes(lastAndUpdated($0)) }
        model["opponents"] = .array(opponents.map(JSONValue.object))

        let players = Set(opponents.compactMap { text($0["player"]) })
        model["players"] = .array(players.sorted { ($0.lowercased(), $0) < ($1.lowercased(), $1) }.map(JSONValue.string))
    }

    // MARK: - Pieces, each named after the server function it mirrors

    /// `opponents._faced`: linked by id, or (for a game without links) by the commander's name.
    static func faced(_ opponent: Object, _ game: Object) -> Bool {
        let ids = game["opponent_ids"]?.array ?? []
        if let id = opponent["id"], ids.contains(id) { return true }
        if ids.contains(where: { $0.string?.isEmpty == false }) { return false }
        let commanders = Set((opponent["commanders"]?.array ?? []).compactMap { $0.string?.lowercased() })
        return (game["opponents"]?.array ?? []).contains { $0.string.map { commanders.contains($0.lowercased()) } ?? false }
    }

    /// `appdata._record`.
    static func record(_ games: [Object]) -> Object {
        func count(_ result: String) -> JSONValue { .int(games.filter { $0["result"]?.string == result }.count) }
        let last = games.compactMap { $0["played"]?.string }.max()
        return ["games": .int(games.count), "wins": count("win"), "losses": count("loss"), "draws": count("draw"),
                "last": last.map(JSONValue.string) ?? .null]
    }

    /// `opponents.title`: "Label (Commander)" or just the commander(s).
    static func title(_ opponent: Object) -> String {
        let commanders = (opponent["commanders"]?.array ?? []).compactMap(\.string).joined(separator: " + ")
        let shown = commanders.isEmpty ? "?" : commanders
        return text(opponent["label"]).map { "\($0) (\(shown))" } ?? shown
    }

    /// `appops._match`: by id, else the most recently updated opponent deck led by this commander.
    static func match(_ opponents: [Object], _ slot: Object) -> Int? {
        if let id = slot["id"]?.string, let index = opponents.firstIndex(where: { $0["id"]?.string == id }) { return index }
        guard let name = text(slot["commander"])?.lowercased() else { return nil }
        let hits = opponents.indices.filter { i in
            (opponents[i]["commanders"]?.array ?? []).contains { $0.string?.lowercased() == name }
        }
        return hits.max { (opponents[$0]["updated"]?.string ?? "") < (opponents[$1]["updated"]?.string ?? "") }
    }

    /// `appops._new_opponent`, in the read model's shape; nil without a commander (the server refuses it).
    static func newOpponent(_ fields: Object, at: String, tags known: Set<String>?) -> Object? {
        let commanders = (fields["commanders"]?.array ?? []).compactMap { text($0) }.prefix(2)
        guard !commanders.isEmpty else { return nil }
        let id = fields["id"]?.string ?? String(PendingOp.newID().prefix(8))
        return ["id": .string(id), "title": .null, "label": .string(text(fields["label"]) ?? ""),
                "player": .string(text(fields["player"]) ?? ""), "commanders": .array(commanders.map(JSONValue.string)),
                "colors": .string(colors(fields["colors"])), "bracket": .null, "tags": cleanKeys(fields["tags"], known: known),
                "notes": .array([]), "record": .null, "updated": .string(at), "created": .string(at)]
    }

    /// The keys of one of the read model's quick-pick lists (`options.tags`, `options.issues`): what the
    /// server keeps. nil from a model without them.
    static func known(_ model: Object, _ list: String) -> Set<String>? {
        guard let options = model["options"]?[list]?.array else { return nil }
        return Set(options.compactMap { $0[0]?.string })
    }

    /// Tags or issues as the server keeps them: known ones only, each once, in the given order.
    static func cleanKeys(_ value: JSONValue?, known: Set<String>?) -> JSONValue {
        var seen = Set<String>()
        let kept = (value?.array ?? []).compactMap(\.string).filter { (known?.contains($0) ?? true) && seen.insert($0).inserted }
        return .array(kept.map(JSONValue.string))
    }

    static func makeNote(_ id: String, _ text: String, at: String, game: String? = nil, deck: String? = nil) -> Object {
        ["id": .string(id), "text": .string(text), "at": .string(at),
         "game_id": game.map(JSONValue.string) ?? .null, "deck_slug": deck.map(JSONValue.string) ?? .null]
    }

    /// `games.clean_places`: places 1…N (N = the user plus the opponents, at most 6; ties allowed).
    static func cleanPlaces(_ place: JSONValue?, _ theirs: [JSONValue], opponents: Int) -> (Int?, [Int?]?) {
        let top = opponents > 0 ? min(6, 1 + opponents) : 6
        func ok(_ value: JSONValue?) -> Int? { value?.int.flatMap { (1...top).contains($0) ? $0 : nil } }
        let places = (0..<opponents).map { ok(theirs.indices.contains($0) ? theirs[$0] : nil) }
        return (ok(place), places.contains { $0 != nil } ? places : nil)
    }

    /// `storage.list_rank`: pinned first (newly pinned on top, then in the dragged order), shelved last.
    static func rank(_ deck: Object) -> [Double] {
        let pinned = deck["pinned"]?.bool == true
        let group = (deck["shelved"]?.bool == true ? 2.0 : 0) + (pinned ? 0 : 1)
        let pinRank: Double? = pinned ? deck["pin_rank"]?.int.map(Double.init) : nil
        return [group, pinRank == nil ? 0 : 1, pinRank ?? 0]
    }

    static func lastAndUpdated(_ item: Object) -> [String] {
        [item["record"]?["last"]?.string ?? "", item["updated"]?.string ?? ""]
    }

    // MARK: - JSON helpers

    static func objects(_ value: JSONValue?) -> [Object] { (value?.array ?? []).compactMap(\.object) }

    /// A trimmed, non-empty string.
    static func text(_ value: JSONValue?) -> String? {
        guard let text = value?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }

    /// Colour letters in WUBRG order, from "BG" or ["B", "G"].
    static func colors(_ value: JSONValue?) -> String {
        let given = value?.string ?? (value?.array ?? []).compactMap(\.string).joined()
        return "WUBRG".filter { given.contains($0) }
    }

    /// Swift's `sort` doesn't promise to keep equal items in order; the server's (Python's) does.
    static func stableSorted(_ items: [Object], by before: (Object, Object) -> Bool) -> [Object] {
        items.enumerated().sorted { a, b in
            before(a.element, b.element) || (!before(b.element, a.element) && a.offset < b.offset)
        }.map(\.element)
    }
}

