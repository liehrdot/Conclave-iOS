import Foundation

/// The cards the phone has looked up, by name, kept on disk: a card opened once shows again offline,
/// and a deck's cards are looked up together in one request when its page opens. Mirrors the name
/// cache and `info()` in the PWA's `scry.js`.
public actor CardLibrary {
    let scryfall: Scryfall
    /// The file, or nil to keep the cards in memory only (screenshots, tests).
    let file: URL?
    private var cards: [String: Card] = [:]
    /// Names Scryfall didn't know this session, so they aren't asked again and again.
    private var unknown: Set<String> = []
    private var loaded = false

    public init(scryfall: Scryfall, file: URL?) {
        self.scryfall = scryfall
        self.file = file
    }

    /// The card when it was looked up before; never asks Scryfall.
    public func cached(_ name: String) -> Card? {
        load()
        return cards[name]
    }

    /// The card, from the saved ones or from Scryfall; nil when Scryfall doesn't know the name.
    /// Throws `CardError` when it isn't saved and Scryfall can't be reached.
    public func card(named name: String) async throws -> Card? {
        if let card = cached(name) { return card }
        if unknown.contains(name) { return nil }
        try await lookUp([name])
        return cards[name]
    }

    /// Looks up the names not saved yet, in as few requests as possible. Failures are quiet: the card
    /// view asks again for the one card it shows.
    public func prefetch(_ names: [String]) async {
        load()
        let missing = Array(Set(names.filter { cards[$0] == nil && !unknown.contains($0) })).sorted()
        if !missing.isEmpty { try? await lookUp(missing) }
    }

    private func lookUp(_ names: [String]) async throws {
        let found = try await scryfall.cards(named: names)
        for name in names {
            guard let card = found[name] else { unknown.insert(name); continue }
            cards[name] = card
            cards[card.name] = card
            cards[card.front] = card
        }
        save()
    }

    /// Keeps cards a search brought (English ones only: the library shows every card in English), so
    /// their card sheet opens at once and offline.
    public func remember(_ found: [Card]) {
        load()
        for card in found where card.lang == "en" {
            cards[card.name] = card
            cards[card.front] = card
        }
        save()
    }

    /// Forgets the saved cards (signing out: they came with that account's decks).
    public func clear() {
        cards = [:]
        unknown = []
        if let file { try? FileManager.default.removeItem(at: file) }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let file, let data = try? Data(contentsOf: file),
              let saved = try? JSONDecoder().decode([String: Card].self, from: data) else { return }
        cards = saved.merging(cards) { _, new in new }
    }

    private func save() {
        guard let file, let data = try? JSONEncoder().encode(cards) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }
}
