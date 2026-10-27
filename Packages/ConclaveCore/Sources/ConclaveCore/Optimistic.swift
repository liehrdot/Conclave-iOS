import Foundation

/// Shows the phone's own changes before the server has them: applies the outbox's operations to a copy of
/// the read model, the way the server will (`appops.apply`, then `appdata.snapshot`'s records and order).
/// Mirrors `apply()` and `recompute()` in the PWA's `data.js`, checked against Conclave's shared cases
/// (`ops.json`) in `OptimisticTests`.
///
/// It works on the raw JSON, not on `ReadModel`, so keys the app doesn't model survive. Games, opponent
/// decks, the collection and `deck.edit` for now; the other deck types leave the model as it is until their
/// screens come.
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
        case "collection.add":
            addToCollection(p, op: op, in: &model)
        case "collection.update":
            changeCollection(p, in: &model)
        case "deck.edit":
            editDeck(p, op: op, in: &model)
        default:
            break  // decks: not shown at once yet
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

    /// `appops._collection_add`: more copies of the entry with the same printing and place, else a new
    /// entry; a negative `qty` takes copies away again (the undo of an add).
    static func addToCollection(_ p: JSONValue, op: PendingOp, in model: inout Object) {
        guard let e = p["entry"]?.object, let qty = e["qty"]?.int, qty != 0, (-99...99).contains(qty),
              let name = text(e["name"]).map({ String($0.prefix(160)) }) else { return }
        let (place, placeDeck) = cleanPlace(e["place"], e["place_deck"])
        var entry: Object = [
            "name": .string(name), "qty": .int(qty), "proxy": .bool(e["proxy"]?.bool == true), "foil": .bool(e["foil"]?.bool == true),
            "lang": .string(e["lang"]?.string.flatMap { languages.contains($0) ? $0 : nil } ?? "en"),
            "set": matching(e["set"]?.string?.lowercased(), isSetCode).map(JSONValue.string) ?? .null,
            "set_name": text(e["set_name"]).map { .string(String($0.prefix(120))) } ?? .null,
            "collector_number": matching(e["collector_number"]?.string, isCollectorNumber).map(JSONValue.string) ?? .null,
            "scryfall_id": matching(e["scryfall_id"]?.string, isScryfallID).map(JSONValue.string) ?? .null,
            "price_eur": matching(e["price_eur"]?.string, isPrice).map(JSONValue.string) ?? .null,
            "place": .string(place), "place_deck": .string(placeDeck),
        ]
        var items = objects(model["collection"])
        if let hit = items.firstIndex(where: { collectionKey($0) == collectionKey(entry) }) {
            let left = min(9999, (items[hit]["qty"]?.int ?? 0) + qty)
            if left > 0 { items[hit]["qty"] = .int(left) } else { items.remove(at: hit) }
        } else {
            guard qty > 0 else { return }  // nothing left to take away
            let taken = Set(items.compactMap { $0["id"]?.string })
            let id = e["id"]?.string.flatMap { isID($0) && !taken.contains($0) ? $0 : nil }
            entry["id"] = .string(id ?? op.id)
            if entry["scryfall_id"] == .null, let image = e["image"]?.string,
               image.hasPrefix("https://cards.scryfall.io/"), image.count < 300 {
                entry["image"] = .string(image)  // the read model keeps a picture only where the id can't give one
            }
            items.append(entry)
        }
        model["collection"] = .array(items.map(JSONValue.object))
    }

    /// `appops._collection_update`: `id` plus `qty` (0 deletes), `proxy`, `foil`, `lang`, `place` and
    /// `place_deck`; then entries that now describe the same printing and place become one.
    static func changeCollection(_ p: JSONValue, in model: inout Object) {
        var items = objects(model["collection"])
        guard let index = items.firstIndex(where: { $0["id"] != nil && $0["id"] == p["id"] }) else { return }
        var entry = items[index]
        if let qty = p["qty"] {
            guard let qty = qty.int, (0...9999).contains(qty) else { return }  // the server refuses it
            entry["qty"] = .int(qty)
        }
        for key in ["proxy", "foil"] where p[key] != nil {
            entry[key] = .bool(p[key]?.bool == true)
        }
        if let lang = p["lang"] { entry["lang"] = .string(lang.string.flatMap { languages.contains($0) ? $0 : nil } ?? "en") }
        if p["place"] != nil || p["place_deck"] != nil {
            let (place, placeDeck) = cleanPlace(p["place"] ?? entry["place"], p["place_deck"] ?? entry["place_deck"])
            entry["place"] = .string(place)
            entry["place_deck"] = .string(placeDeck)
        }
        guard entry != items[index] else { return }
        items[index] = entry
        var merged: [Object] = []
        var seen: [[String]: Int] = [:]
        for item in items {
            let key = collectionKey(item)
            if let at = seen[key] {
                merged[at]["qty"] = .int((merged[at]["qty"]?.int ?? 0) + (item["qty"]?.int ?? 0))
            } else {
                seen[key] = merged.count
                merged.append(item)
            }
        }
        model["collection"] = .array(merged.filter { ($0["qty"]?.int ?? 0) > 0 }.map(JSONValue.object))
    }

    /// `appops._deck_edit`: `add` (quantities add up, at most 99), `remove`, `set_qty` (0 removes), `set_category`,
    /// then the maybe list like `maybe.change` (deck cards leave it, `maybe_remove`, `maybe_add` moves a deck card
    /// there). A commander anywhere refuses the whole op; no change, no new version. The PC checks it later.
    static func editDeck(_ p: JSONValue, op: PendingOp, in model: inout Object) {
        var decks = objects(model["decks"])
        guard let slug = p["deck"]?.string, let index = decks.firstIndex(where: { $0["slug"]?.string == slug }) else { return }
        var deck = decks[index]
        let commanders = Set((deck["commanders"]?.array ?? []).compactMap(\.string))
        func category(_ value: JSONValue?) -> String? { value?.string.flatMap { categories.contains($0) ? $0 : nil } }
        var cards: [String: Object] = [:]
        for card in objects(deck["cards"]) { if let name = card["name"]?.string { cards[name] = card } }
        var maybe: [String: Object] = [:]
        for card in objects(deck["maybe"]) { if let name = card["name"]?.string { maybe[name] = card } }
        let (cardsBefore, maybeBefore) = (cards, maybe)
        for a in objects(p["add"]) {
            guard let name = text(a["name"]), !commanders.contains(name) else { return }  // the server refuses it
            let qty = a["qty"].map { $0.int ?? -1 } ?? 1
            guard (0...99).contains(qty) else { return }
            if let have = cards[name]?["qty"]?.int {
                cards[name]?["qty"] = .int(min(99, have + max(1, qty)))
            } else {
                cards[name] = ["name": .string(name), "qty": .int(max(1, qty)), "category": .string(category(a["category"]) ?? "Synergy")]
            }
        }
        for name in (p["remove"]?.array ?? []).compactMap(\.string) { cards[name] = nil }
        for (name, qty) in p["set_qty"]?.object ?? [:] {
            guard let qty = qty.int, (0...99).contains(qty) else { return }
            if cards[name] == nil { continue }
            if qty == 0 { cards[name] = nil } else { cards[name]?["qty"] = .int(qty) }
        }
        for (name, value) in p["set_category"]?.object ?? [:] {
            if cards[name] != nil, let cat = category(value) { cards[name]?["category"] = .string(cat) }
        }
        for name in maybe.keys where cards[name] != nil { maybe[name] = nil }  // went into the deck
        for name in (p["maybe_remove"]?.array ?? []).compactMap(\.string) { maybe[name] = nil }
        for a in objects(p["maybe_add"]) {
            guard let name = text(a["name"]), !commanders.contains(name) else { return }
            let card = cards.removeValue(forKey: name)
            if maybe[name] != nil && card == nil { continue }
            let cat = category(a["category"]) ?? card?["category"]?.string.flatMap { $0.isEmpty ? nil : $0 } ?? "Synergy"
            maybe[name] = ["name": .string(name), "category": .string(cat)]
        }
        guard cards != cardsBefore || maybe != maybeBefore else { return }  // no new version
        deck["cards"] = .array(cards.keys.sorted(by: codepoints).compactMap { cards[$0] }.map(JSONValue.object))
        deck["maybe"] = .array(maybe.keys.sorted(by: codepoints).compactMap { maybe[$0] }.map(JSONValue.object))
        deck["version"] = .int((deck["version"]?.int ?? 0) + 1)
        deck["updated"] = .string(op.at)
        deck["checking"] = .bool(true)
        decks[index] = deck
        model["decks"] = .array(decks.map(JSONValue.object))
    }

    /// `appops.CATEGORIES`.
    static let categories: Set = ["Ramp", "Draw", "Removal", "Board Wipe", "Counterspell", "Tutor", "Protection",
                                  "Synergy", "Win Condition", "Utility", "Land"]

    /// Python's `sorted()` on strings: by code point, not by locale.
    static func codepoints(_ a: String, _ b: String) -> Bool { a.unicodeScalars.lexicographicallyPrecedes(b.unicodeScalars) }

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

        if let collection = model["collection"]?.array {  // `appdata.collection`: by name
            let sorted = stableSorted(collection.compactMap(\.object)) {
                ($0["name"]?.string ?? "").lowercased() < ($1["name"]?.string ?? "").lowercased()
            }
            model["collection"] = .array(sorted.map(JSONValue.object))
        }
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

    /// `appops._coll_key` (the PC's `collection._key`): one entry per name, printing, proxy, foil,
    /// language and place; a deck place ignores the free text, and the text ignores case.
    static func collectionKey(_ e: Object) -> [String] {
        let deck = e["place_deck"]?.string ?? ""
        return [(e["name"]?.string ?? "").lowercased(), e["scryfall_id"]?.string ?? "", String(e["proxy"]?.bool == true),
                String(e["foil"]?.bool == true), e["lang"]?.string ?? "en", deck,
                deck.isEmpty ? (e["place"]?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() : ""]
    }

    /// `appops._place` (the PC's `collection.clean_place`): the text with its spaces tidied, at most 80
    /// characters, and a deck slug or "".
    static func cleanPlace(_ place: JSONValue?, _ deck: JSONValue?) -> (String, String) {
        let words = (place?.string ?? "").split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let slug = matching(deck?.string, isDeckSlug) ?? ""
        return (String(words.prefix(80)), slug)
    }

    /// `LANGS`: the languages the server keeps; any other becomes English.
    static let languages: Set = ["en", "de", "fr", "it", "es", "pt", "ja", "ko", "ru", "zhs", "zht", "ph"]

    /// The trimmed value when it passes `check`, like `appops._match_str`.
    static func matching(_ value: String?, _ check: (String) -> Bool) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty, check(value) else { return nil }
        return value
    }

    // The server's patterns (`SET_RE`, `NUMBER_RE`, `UUID_RE`, `PRICE_RE`, `ID_RE`, `PLACE_DECK_RE`).
    static func isSetCode(_ s: String) -> Bool { (2...8).contains(s.count) && s.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber) } }
    static func isCollectorNumber(_ s: String) -> Bool {
        (1...12).contains(s.count) && s.allSatisfy { $0.isLetter || $0.isNumber || "_★†-".contains($0) }
    }
    static func isScryfallID(_ s: String) -> Bool {
        let groups = s.split(separator: "-", omittingEmptySubsequences: false)
        return groups.map(\.count) == [8, 4, 4, 4, 12] && s.allSatisfy { $0 == "-" || ($0.isHexDigit && !$0.isUppercase) }
    }
    static func isPrice(_ s: String) -> Bool {
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count), (1...6).contains(parts[0].count), parts.allSatisfy({ $0.allSatisfy { $0.isASCII && $0.isNumber } }) else { return false }
        return parts.count == 1 || (1...2).contains(parts[1].count)
    }
    static func isID(_ s: String) -> Bool { (1...40).contains(s.count) && s.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") } }
    static func isDeckSlug(_ s: String) -> Bool {
        guard let first = s.first, (1...81).contains(s.count) else { return false }
        func ok(_ c: Character) -> Bool { c.isASCII && (c.isLowercase || c.isNumber) }
        return ok(first) && s.allSatisfy { ok($0) || $0 == "-" }
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

