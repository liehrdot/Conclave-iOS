import Foundation

/// What pairing needs: the sync server's address and the one-time code (`ABCD-EFGH`).
///
/// The PWA lives on the server, so it never had to ask where the server is. The native app does:
/// a pairing link or QR code carries the address (`https://sync.example.org/koppeln#ABCD-EFGH`),
/// a bare code needs the address typed next to it. Mirrors `parsePairing` in Conclave Table.
public struct Pairing: Equatable, Sendable {
    public let server: URL
    public let code: String

    /// Pairing codes leave out letters that look alike (I, O) and the digits 0 and 1.
    /// (A computed property: a Regex isn't Sendable, so Swift 6 refuses it as a shared constant.)
    static var codePattern: Regex<(Substring, Substring, Substring)> {
        /([A-HJ-NP-Z2-9]{4})-?([A-HJ-NP-Z2-9]{4})/.ignoresCase()
    }

    /// A link, or a code plus `server` for a bare code; nil when it is neither.
    public static func parse(_ text: String, server: String = "") -> Pairing? {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let isLink = raw.range(of: #"^https?://"#, options: [.regularExpression, .caseInsensitive]) != nil
        let link = isLink ? URLComponents(string: raw) : nil
        if isLink && link == nil { return nil }
        let codeText = link.map { $0.fragment ?? "" } ?? raw
        guard let match = codeText.firstMatch(of: codePattern) else { return nil }
        let address = link.flatMap(origin) ?? normalizeServer(server)
        guard let address else { return nil }
        return Pairing(server: address, code: "\(match.1)-\(match.2)".uppercased())
    }

    /// `sync.example.org` or `https://sync.example.org/app/` → `https://sync.example.org`; nil when it isn't one.
    public static func normalizeServer(_ text: String) -> URL? {
        var raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty { return nil }
        if raw.range(of: #"^https?://"#, options: [.regularExpression, .caseInsensitive]) == nil { raw = "https://\(raw)" }
        return URLComponents(string: raw).flatMap(origin)
    }

    /// Scheme, host and port only: a server is always addressed at its root.
    /// Plain http only for `localhost` (a test server on the same machine): the token travels in every
    /// request, so anywhere else it must be https. Stricter than Conclave Table, which runs in a browser.
    static func origin(_ parts: URLComponents) -> URL? {
        guard let scheme = parts.scheme?.lowercased(),
              let host = parts.host?.lowercased(), host.contains(".") || host == "localhost",
              scheme == "https" || (scheme == "http" && host == "localhost")
        else { return nil }
        var root = URLComponents()
        root.scheme = scheme
        root.host = host
        root.port = parts.port
        return root.url
    }

    /// The server as people read it: `sync.example.org`, with the port when there is one.
    public var host: String {
        let parts = URLComponents(url: server, resolvingAgainstBaseURL: false)
        return (parts?.host ?? "") + (parts?.port.map { ":\($0)" } ?? "")
    }
}
