/// The read model's ETag, `"<server_id>-<epoch>-<seq>"`.
///
/// Caddy, in front of the sync server, appends its compression to the header (`…-12-zstd`), and a
/// weak tag starts with `W/`. Comparing whole headers would then see a change on every request, and a
/// plain split would read the wrong seq; that is how sent games once stuck on the phone (Conclave PR #5).
/// So the app only ever looks at the core. Mirrors `tagCore` / `seqOf` in the PWA's `data.js`.
public enum ETag {
    /// `W/"ab12-3f-42-zstd"` → `ab12-3f-42`; "" when the header isn't one of ours.
    public static func core(_ header: String?) -> String {
        var text = header ?? ""
        if text.hasPrefix("W/") { text.removeFirst(2) }
        let parts = text.replacingOccurrences(of: "\"", with: "").split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count >= 3,
              parts[0...1].allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isHexDigit) }),
              !parts[2].isEmpty, parts[2].allSatisfy(\.isASCIIDigit)
        else { return "" }
        return parts[0...2].joined(separator: "-")
    }

    /// The server's change counter in the tag; 0 when there is none.
    public static func seq(_ header: String?) -> Int {
        Int(core(header).split(separator: "-").last ?? "") ?? 0
    }
}

extension Character {
    fileprivate var isASCIIDigit: Bool { isASCII && isNumber }
}
