import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// What can go wrong asking Scryfall.
public enum CardError: Error, Equatable, Sendable {
    /// No answer: no network or Scryfall is down. Cards already looked up still show.
    case offline
    case failed(status: Int)
    /// Scryfall couldn't read a search (a typo in the syntax); its own words, when it gave them.
    case badQuery(String)
}

/// One page of a search: up to 175 cards, most played in Commander first.
public struct SearchPage: Equatable, Sendable {
    public var cards: [Card]
    /// All hits, on every page.
    public var total: Int
    /// The next page's number; nil on the last page.
    public var next: Int?
}

/// One answer to a name typed in the search field. A name the autocomplete found has no card yet:
/// the card sheet looks it up by name.
public struct NameHit: Equatable, Sendable, Identifiable {
    public var id: String { name }
    /// The English (Oracle) name.
    public var name: String
    /// The German printed name, when the German name was what matched.
    public var german: String?
    public var type: String
    /// The card in English, when the search already brought it.
    public var card: Card?

    init(name: String, german: String?, type: String, card: Card?) {
        self.name = name
        self.german = german
        self.type = type
        self.card = card
    }

    /// A card a search found (English): its name and type line, faces joined by " // ".
    public init(_ card: Card) {
        self.init(name: card.name, german: nil, type: card.faces.map(\.typeLine).joined(separator: " // "), card: card)
    }

    /// The card named exactly as typed first (English or German), then cards that only carry it as their
    /// front face ("Rampant Growth" before "Studious First-Year // Rampant Growth"); otherwise the order
    /// stays. Mirrors `exactFirst()` in `scry.js`.
    public static func exactFirst(_ hits: [NameHit], _ query: String) -> [NameHit] {
        let typed = query.trimmingCharacters(in: .whitespaces).lowercased()
        func rank(_ hit: NameHit) -> Int {
            let name = hit.name.lowercased()
            if name == typed || hit.german?.lowercased() == typed { return 0 }
            return name.hasPrefix("\(typed) // ") ? 1 : 2
        }
        return hits.enumerated().sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }.map(\.element)
    }
}

/// Scryfall's API, straight from the phone (no key, no server of ours in between). Like `api()` in the
/// PWA's `scry.js`: requests at least 100 ms apart, as Scryfall asks (50–100 ms), and the
/// `Accept` and `User-Agent` headers it requires.
public actor Scryfall {
    public static let api = URL(string: "https://api.scryfall.com")!
    /// Names per `/cards/collection` request; Scryfall takes at most 75.
    public static let batch = 75

    let transport: any Transport
    let gap: Duration
    private var free = ContinuousClock.now

    public init(transport: any Transport, gap: Duration = .milliseconds(100)) {
        self.transport = transport
        self.gap = gap
    }

    /// Looks names up with `POST /cards/collection`, keyed by the name asked. Names Scryfall doesn't
    /// know are left out. A card is asked by its front face: Scryfall doesn't find "Front // Back" by
    /// the whole name.
    public func cards(named names: [String]) async throws -> [String: Card] {
        var found: [String: Card] = [:]
        var start = 0
        while start < names.count {
            let part = Array(names[start..<min(start + Self.batch, names.count)])
            start += Self.batch
            struct Answer: Decodable { var data: [ScryfallCard] }
            let body = ["identifiers": part.map { ["name": $0.components(separatedBy: " // ")[0]] }]
            var request = URLRequest(url: Self.api.appending(path: "cards/collection"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
            let data = try await send(request)
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            guard let answer = try? decoder.decode(Answer.self, from: data) else { throw CardError.failed(status: 200) }
            var byName: [String: Card] = [:]
            for card in answer.data.map(\.card) {
                byName[card.name.lowercased()] = card
                byName[card.front.lowercased()] = card
            }
            for name in part {
                if let card = byName[name.lowercased()] ?? byName[name.components(separatedBy: " // ")[0].lowercased()] {
                    found[name] = card
                }
            }
        }
        return found
    }

    /// Any Scryfall query, like `searchQuery()` in `scry.js`: one page, Commander's most played first
    /// (`order=edhrec`), one entry per card. No hits is an empty page (Scryfall answers 404); a query it
    /// can't read throws `CardError.badQuery`. `multilingual` lets German names match too.
    public func search(_ query: String, page: Int = 1, multilingual: Bool = false) async throws -> SearchPage {
        var items = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "unique", value: "cards"),
                     URLQueryItem(name: "order", value: "edhrec"), URLQueryItem(name: "page", value: String(page))]
        if multilingual { items.append(URLQueryItem(name: "include_multilingual", value: "true")) }
        struct Answer: Decodable { var data: [ScryfallCard]; var totalCards: Int?; var hasMore: Bool? }
        let data: Data
        do {
            data = try await send(URLRequest(url: Self.url("cards/search", items)))
        } catch CardError.failed(status: 404) {
            return SearchPage(cards: [], total: 0, next: nil)
        } catch CardError.failed(status: 400) {
            throw CardError.badQuery("")
        }
        guard let answer = try? Self.decoder.decode(Answer.self, from: data) else { throw CardError.failed(status: 200) }
        return SearchPage(cards: answer.data.map(\.card), total: answer.totalCards ?? answer.data.count,
                          next: answer.hasMore == true ? page + 1 : nil)
    }

    /// The cards a typed name can mean, English or German, like `searchCards()` in `scry.js`: the ten most
    /// played cards whose name (in any language) matches, then the autocomplete's names, at most 15, the
    /// exact name first. Throws only when neither answered.
    public func find(name query: String) async throws -> [NameHit] {
        let typed = query.trimmingCharacters(in: .whitespaces)
        guard !typed.isEmpty else { return [] }
        var hits: [NameHit] = []
        var failure: (any Error)?
        do {
            let items = [URLQueryItem(name: "q", value: typed), URLQueryItem(name: "unique", value: "cards"),
                         URLQueryItem(name: "order", value: "edhrec"), URLQueryItem(name: "include_multilingual", value: "true")]
            struct Answer: Decodable { var data: [ScryfallCard] }
            let data = try await send(URLRequest(url: Self.url("cards/search", items)))
            for found in (try Self.decoder.decode(Answer.self, from: data)).data.prefix(10) {
                let card = found.card
                let german = found.lang == "de" ? found.printedName : nil
                hits.append(NameHit(name: card.name, german: german, type: card.faces.map(\.typeLine).joined(separator: " // "),
                                    card: card.lang == "en" ? card : nil))
            }
        } catch CardError.failed(status: 404) {
            // nothing matched in any language; the autocomplete may still know a start of a name
        } catch {
            failure = error
        }
        do {
            struct Names: Decodable { var data: [String] }
            let url = Self.url("cards/autocomplete", [URLQueryItem(name: "q", value: typed)])
            let names = try JSONDecoder().decode(Names.self, from: try await send(URLRequest(url: url))).data
            for name in names where !hits.contains(where: { $0.name == name }) {
                hits.append(NameHit(name: name, german: nil, type: "", card: nil))
            }
        } catch {
            if let failure, hits.isEmpty { throw failure }
        }
        return Array(NameHit.exactFirst(hits, typed).prefix(15))
    }

    /// An API address with its query. A "+" is encoded too: left as is, it would arrive as a space
    /// ("o:+1/+1" is a real search).
    static func url(_ path: String, _ items: [URLQueryItem]) -> URL {
        var parts = URLComponents(url: api.appending(path: path), resolvingAgainstBaseURL: false)!
        parts.queryItems = items
        parts.percentEncodedQuery = parts.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return parts.url!
    }

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    private func send(_ request: URLRequest) async throws -> Data {
        var request = request
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Conclave-iOS/1.0", forHTTPHeaderField: "User-Agent")
        // take the next free start time before waiting: the actor lets other calls in while this one
        // sleeps or waits for its answer, and each must start `gap` after the one before
        let start = max(free, ContinuousClock.now)
        free = start + gap
        if start > ContinuousClock.now { try? await Task.sleep(until: start) }
        let data: Data, response: HTTPURLResponse
        do { (data, response) = try await transport.send(request) } catch { throw CardError.offline }
        guard (200..<300).contains(response.statusCode) else { throw CardError.failed(status: response.statusCode) }
        return data
    }
}
