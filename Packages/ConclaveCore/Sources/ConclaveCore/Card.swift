import Foundation

/// A card as the card view shows it: Oracle text and Scryfall's default printing (English). The read
/// model has only names, so this comes from Scryfall itself, like `pick()` in the PWA's `scry.js`.
public struct Card: Codable, Equatable, Sendable {
    /// One face: a normal card has one, a double-faced, split or adventure card two (or more).
    public struct Face: Codable, Equatable, Sendable {
        public var name: String
        public var manaCost: String
        public var typeLine: String
        public var text: String
        /// "2/3", "Loyalty 4" or "Defense 5"; nil when the face has none.
        public var stats: String?
        /// The face's own picture; only double-faced cards have one per face.
        public var image: URL?
    }

    public var name: String
    public var faces: [Face]
    /// Colour identity letters ("BG").
    public var colors: String
    /// The front picture (a split or adventure card has one for both faces).
    public var image: URL?
    public var art: URL?
    /// The card's page on scryfall.com.
    public var link: URL?
    public var lang: String

    /// The back picture of a double-faced card: the second face's own image.
    public var back: URL? { faces.count > 1 ? faces[1].image : nil }

    /// The name before " // ".
    public var front: String { name.components(separatedBy: " // ")[0] }
}

/// Scryfall's card object, only the keys `Card` needs.
struct ScryfallCard: Decodable {
    struct Images: Decodable { var normal: URL?; var artCrop: URL? }
    struct Face: Decodable {
        var name: String?
        var manaCost: String?
        var typeLine: String?
        var oracleText: String?
        var power: String?
        var toughness: String?
        var loyalty: String?
        var defense: String?
        var imageUris: Images?
    }

    var name: String
    var lang: String?
    var manaCost: String?
    var typeLine: String?
    var oracleText: String?
    var power: String?
    var toughness: String?
    var loyalty: String?
    var defense: String?
    var colorIdentity: [String]?
    var imageUris: Images?
    var cardFaces: [Face]?
    var scryfallUri: URL?

    var card: Card {
        func stats(_ power: String?, _ toughness: String?, _ loyalty: String?, _ defense: String?) -> String? {
            if let power, let toughness { return "\(power)/\(toughness)" }
            if let loyalty { return "Loyalty \(loyalty)" }
            if let defense { return "Defense \(defense)" }
            return nil
        }
        let faces: [Card.Face]
        if let cardFaces, !cardFaces.isEmpty {
            faces = cardFaces.map {
                Card.Face(name: $0.name ?? name, manaCost: $0.manaCost ?? "", typeLine: $0.typeLine ?? "",
                          text: $0.oracleText ?? "", stats: stats($0.power, $0.toughness, $0.loyalty, $0.defense),
                          image: $0.imageUris?.normal)
            }
        } else {
            faces = [Card.Face(name: name, manaCost: manaCost ?? "", typeLine: typeLine ?? "", text: oracleText ?? "",
                               stats: stats(power, toughness, loyalty, defense), image: imageUris?.normal)]
        }
        let images = imageUris ?? cardFaces?.first?.imageUris
        return Card(name: name, faces: faces, colors: (colorIdentity ?? []).joined(), image: images?.normal,
                    art: images?.artCrop, link: scryfallUri, lang: lang ?? "en")
    }
}
