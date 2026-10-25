import Foundation

/// The read model the phone got last, kept on disk with its ETag, so the app opens with its decks at
/// once and offline. Mirrors `amtisch.base` and `refresh()` in the PWA's `data.js`. The JSON is kept as
/// the server sent it: a newer server's keys survive an older app.
public struct ReadModelCache: Sendable {
    /// A folder of its own (the app's is in Application Support, never in Caches: iOS may empty those).
    public let folder: URL

    public init(folder: URL) { self.folder = folder }

    private var dataFile: URL { folder.appending(path: "readmodel.json") }
    private var tagFile: URL { folder.appending(path: "readmodel.etag") }

    /// The saved read model and its tag; nil before the first download or when the file is damaged.
    public func load() -> (model: ReadModel, etag: String)? {
        guard let data = try? Data(contentsOf: dataFile), let model = try? ReadModel.decode(data) else { return nil }
        return (model, (try? String(contentsOf: tagFile, encoding: .utf8)) ?? "")
    }

    /// The saved read model as raw JSON, with its tag: the base `Optimistic.apply` builds on.
    public func loadJSON() -> (json: JSONValue, etag: String)? {
        guard let data = try? Data(contentsOf: dataFile), let json = try? JSONDecoder().decode(JSONValue.self, from: data) else { return nil }
        return (json, (try? String(contentsOf: tagFile, encoding: .utf8)) ?? "")
    }

    public func save(_ data: Data, etag: String) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try data.write(to: dataFile, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        try Data(etag.utf8).write(to: tagFile, options: .atomic)
    }

    /// Forgets the copy, when the phone is signed off: the decks belong to that account.
    public func clear() {
        try? FileManager.default.removeItem(at: dataFile)
        try? FileManager.default.removeItem(at: tagFile)
    }

    /// Asks the server for a newer read model than the saved one. Returns it when it changed, nil when
    /// the saved one is still current; throws what `Server` throws (offline, signed off, …), and then
    /// the saved copy stays as it was. A body that doesn't decode is not saved.
    public func refresh(from server: Server) async throws -> ReadModel? {
        switch try await server.readModel(etag: load()?.etag) {
        case .unchanged:
            return nil
        case .changed(let data, let etag):
            let model = try ReadModel.decode(data)
            try save(data, etag: etag)
            return model
        }
    }
}
