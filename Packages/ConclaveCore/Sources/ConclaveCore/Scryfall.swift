import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// What can go wrong asking Scryfall.
public enum CardError: Error, Equatable, Sendable {
    /// No answer: no network or Scryfall is down. Cards already looked up still show.
    case offline
    case failed(status: Int)
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
