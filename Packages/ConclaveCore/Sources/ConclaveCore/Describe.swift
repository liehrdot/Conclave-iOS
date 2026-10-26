import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The sync server's card search by description ("Describe", the one AI feature Flo allowed): the
/// server asks Claude with the owner's API key to turn a description into Scryfall syntax; the phone
/// then searches Scryfall itself. Mirrors `bindDescribe()` in the PWA's `screens.js` and `aiPage` in
/// `forms.js`; routes `POST /api/app/cards/describe` and `GET|PUT /api/app/ai`.
public struct DescribeAnswer: Decodable, Equatable, Sendable {
    /// Scryfall syntax with the colours, types and `f:commander` already in.
    public var query: String
    /// A wider search for when `query` finds nothing; empty when there is none.
    public var broader: String
    /// One German sentence about the query (the server asks for German; the app doesn't show it).
    public var explain: String
    /// The server had this description already: it cost nothing.
    public var cached: Bool

    public init(query: String, broader: String = "", explain: String = "", cached: Bool = false) {
        self.query = query
        self.broader = broader
        self.explain = explain
        self.cached = cached
    }
}

/// How the server's description search is set up. The key itself never leaves the server.
public struct AISettings: Decodable, Equatable, Sendable {
    public struct Model: Decodable, Equatable, Sendable, Identifiable {
        public var id: String
        public var label: String
    }

    public var configured: Bool
    public var model: String
    /// The key comes from the server's environment, so the phone can't change it.
    public var fromEnv: Bool
    /// The key's last four characters ("…a1b2"), to recognise it.
    public var keyHint: String
    public var models: [Model]
}

/// The colours and card types the description search can be narrowed to, as the server takes them.
public enum DescribeFilter {
    /// W U B R G, and C for colourless (with other colours: "these, or colourless").
    public static let colors = ["W", "U", "B", "R", "G", "C"]
    public static let types = ["creature", "instant", "sorcery", "artifact", "enchantment", "planeswalker", "land"]
}

extension Server {
    /// A description → Scryfall syntax. Not set up yet answers 409 (`ServerError.needsSetup`).
    public func describe(_ text: String, colors: [String] = [], types: [String] = []) async throws -> DescribeAnswer {
        struct Body: Encodable { let text: String; let colors: [String]; let types: [String] }
        var request = request("api/app/cards/describe")
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(Body(text: text, colors: colors, types: types))
        return try Self.decode(DescribeAnswer.self, try await Self.send(request, transport: transport, claiming: false))
    }

    public func aiSettings() async throws -> AISettings {
        try Self.decode(AISettings.self, try await Self.send(request("api/app/ai"), transport: transport, claiming: false))
    }

    /// Changes the setup; nil leaves a field as it is, an empty key removes it.
    public func setAI(key: String? = nil, model: String? = nil) async throws -> AISettings {
        var body: [String: String] = [:]
        if let key { body["key"] = key }
        if let model { body["model"] = model }
        var request = request("api/app/ai")
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return try Self.decode(AISettings.self, try await Self.send(request, transport: transport, claiming: false))
    }
}

extension ServerError {
    /// The description search isn't set up on the server yet (409): the app offers the setup.
    public var needsSetup: Bool {
        if case .failed(status: 409, _) = self { return true }
        return false
    }
}
