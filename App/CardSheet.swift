import ConclaveCore
import SwiftUI
import UIKit

/// One card of a deck: the picture of the person's own copy in that deck (its exact printing, foil,
/// language), else Scryfall's printing; double-faced cards turn over; below the Oracle text with mana
/// symbols. The PC's card view shows the same (`renderCardViewFaces()`, „Liegt im Deck“).
struct CardSheet: View {
    let name: String
    /// The person's copies placed in the deck, real ones first (`ReadModel.copies(of:in:)`).
    let copies: [CollectionEntry]
    /// The copies are the deck's (from a deck), or all of the person's (from the Collection tab).
    var inDeck = true
    /// The deck the sheet was opened from: "Add" then offers moving the card between it and its maybe list.
    var deck: Deck? = nil
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var card: Card?
    @State private var problem: String?
    @State private var picked = 0
    @State private var turned = false
    @State private var adding = false
    @State private var addingToDeck = false

    private var copy: CollectionEntry? { copies.indices.contains(picked) ? copies[picked] : copies.first }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    CardPicture(front: front, back: back, foil: copy?.foil == true, turned: $turned)
                        .frame(maxWidth: 360)
                        .frame(maxWidth: .infinity)
                    if back != nil {
                        Button(turned ? "Show Front" : "Turn Over", systemImage: "arrow.trianglehead.2.clockwise.rotate.90") {
                            turned.toggle()
                        }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                    }
                    copiesSection
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(.regularMaterial, in: .rect(cornerRadius: 20)) // content, so a material; the sheet itself is the glass
                    if let card {
                        ForEach(Array(card.faces.enumerated()), id: \.offset) { _, face in
                            FaceText(face: face)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(16)
                                .background(.regularMaterial, in: .rect(cornerRadius: 20)) // content, so a material; the sheet itself is the glass
                        }
                        if let link = card.link {
                            Link(destination: link) {
                                Label("View on Scryfall", systemImage: "safari")
                            }
                            .font(.subheadline)
                        }
                    } else if let problem {
                        Label(problem, systemImage: "wifi.slash")
                            .foregroundStyle(.secondary)
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding()
            }
            // the card's own art, blurred, like the deck screens
            .background { ArtBackdrop(name: name) }
            .navigationTitle(card?.name ?? name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Menu("Add", systemImage: "plus") {
                        if let deck = liveDeck {
                            deckActions(deck)
                        }
                        Button("Add to a Deck…", systemImage: "rectangle.stack.badge.plus") { addingToDeck = true }
                        Button("Add to Collection…", systemImage: "plus.rectangle.on.rectangle") { adding = true }
                    }
                    .disabled(card == nil)
                }
            }
            .sheet(isPresented: $adding) { AddToCollectionView(name: card?.name ?? name) }
            .sheet(isPresented: $addingToDeck) { AddToDeckView(name: card?.name ?? name, card: card) { dismiss() } }
        }
        .task { await load() }
    }

    /// The deck as it is now (a change made here shows at once).
    private var liveDeck: Deck? {
        guard let deck else { return nil }
        return model.library?.decks.first { $0.slug == deck.slug } ?? deck
    }

    /// Moving the card between the deck it was opened from and that deck's maybe list. It saves and closes,
    /// so the toast with "Undo" shows on the deck.
    @ViewBuilder
    private func deckActions(_ deck: Deck) -> some View {
        let shown = card?.name ?? name
        let place = DeckEdit.place(of: shown, in: deck)
        if place != .commander {
            Section(deck.name) {
                if let payload = DeckEdit.add(shown, card: card, to: deck, as: .deck) {
                    Button(place == .maybe ? "Move into the Deck" : place == .none ? "Add to the Deck" : "Add Another Copy",
                           systemImage: "plus.circle") { save(payload) }
                }
                if let payload = DeckEdit.add(shown, card: card, to: deck, as: .maybe) {
                    Button(place == .none ? "Add to the Maybe List" : "Move to the Maybe List",
                           systemImage: "questionmark.circle") { save(payload) }
                }
            }
        }
    }

    private func save(_ payload: JSONValue) {
        Task {
            _ = await model.save("deck.edit", payload)
            dismiss()
        }
    }

    /// Their own copy's printing when they have one in the deck, else Scryfall's.
    private var front: URL? { copy?.imageURL() ?? card?.image }
    private var back: URL? {
        guard let card, card.back != nil else { return nil }
        if let copy, copy.scryfallId != nil { return copy.imageURL(back: true) }
        return card.back
    }

    @ViewBuilder
    private var copiesSection: some View {
        if copies.isEmpty {
            Text("You have no copy of this card in this deck; this is Scryfall's printing.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text((copies.count == 1 ? "Your Copy" : "Your Copies") + (inDeck ? " in This Deck" : ""))
                    .font(.headline)
                if copies.count == 1, let entry = copies.first {
                    CopyRow(entry: entry, selected: false)
                } else {
                    // several printings in the deck (two different Forests): tap one to see its picture
                    ForEach(Array(copies.enumerated()), id: \.element.id) { index, entry in
                        Button {
                            withAnimation(.smooth) {
                                picked = index
                                turned = false
                            }
                        } label: {
                            CopyRow(entry: entry, selected: index == picked)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func load() async {
        do {
            card = try await model.cards.card(named: name)
            if card == nil { problem = "Scryfall doesn't know this card." }
        } catch {
            problem = "Card text needs a connection the first time."
        }
    }
}

/// One copy: printing, language, foil or proxy, how many.
private struct CopyRow: View {
    let entry: CollectionEntry
    let selected: Bool

    var body: some View {
        HStack(spacing: 10) {
            CardImage(url: entry.imageURL(.small))
                .frame(width: 34)
                .clipShape(.rect(cornerRadius: 3))
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.printing ?? entry.name)
                    .font(.subheadline)
                HStack(spacing: 6) {
                    if entry.foil { Tag(text: "Foil", tint: .purple) }
                    if entry.proxy { Tag(text: "Proxy", tint: .orange) }
                    if entry.lang != "en" { Tag(text: Locale.current.localizedString(forLanguageCode: entry.lang) ?? entry.lang, tint: .secondary) }
                    if entry.qty > 1 { Text("×\(entry.qty)").monospacedDigit().foregroundStyle(.secondary) }
                }
                .font(.caption)
            }
            Spacer()
            if selected {
                Image(systemName: "checkmark")
                    .foregroundStyle(.tint)
                    .accessibilityLabel("Shown")
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

/// A small coloured label ("Foil", "Proxy").
struct Tag: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(tint.opacity(0.15), in: .capsule)
            .foregroundStyle(tint)
    }
}

/// One face's name, cost, type, stats and rules text.
private struct FaceText: View {
    let face: Card.Face

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(face.name)
                    .font(.headline)
                Spacer()
                if !face.manaCost.isEmpty { ManaText(face.manaCost, style: .headline) }
            }
            Text([face.typeLine, face.stats].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if !face.text.isEmpty {
                ManaText(face.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The card picture, turned in 3D to its back for double-faced cards (tap it or "Turn Over"), with a
/// moving holo sheen for a foil copy. With Reduce Motion the sides cross-fade and the sheen stands still.
struct CardPicture: View {
    let front: URL?
    let back: URL?
    let foil: Bool
    @Binding var turned: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How far the card is turned: no turn at all with Reduce Motion, where only the opacity changes.
    private var angle: Double { reduceMotion ? 0 : turned ? 180 : 0 }

    var body: some View {
        ZStack {
            face(front).opacity(turned ? 0 : 1)
            if let back {
                face(back)
                    .rotation3DEffect(.degrees(reduceMotion ? 0 : 180), axis: (x: 0, y: 1, z: 0))
                    .opacity(turned ? 1 : 0)
            }
        }
        .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.4)
        .animation(.smooth(duration: 0.5), value: turned)
        .onTapGesture { if back != nil { turned.toggle() } }
        .accessibilityAddTraits(back != nil ? .isButton : [])
        .accessibilityHint(back != nil ? "Turns the card over" : "")
    }

    private func face(_ url: URL?) -> some View {
        CardImage(url: url)
            .overlay { if foil { FoilSheen() } }
            .clipShape(CardShape())
            .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
    }
}

/// The rainbow shimmer of a foil card, sliding slowly across it.
private struct FoilSheen: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var moved = false

    var body: some View {
        GeometryReader { geo in
            LinearGradient(
                colors: [.clear, .pink.opacity(0.35), .yellow.opacity(0.3), .green.opacity(0.3), .cyan.opacity(0.35), .purple.opacity(0.3), .clear],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .frame(width: geo.size.width * 2, height: geo.size.height * 2)
            .offset(x: moved ? -geo.size.width * 0.2 : -geo.size.width * 0.8, y: moved ? -geo.size.height * 0.2 : -geo.size.height * 0.8)
            .blendMode(.overlay)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) { moved = true }
        }
    }
}

/// A card image from Scryfall's CDN with the card's shape while it loads.
struct CardImage: View {
    let url: URL?
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                RoundedRectangle(cornerRadius: 14)
                    .fill(.quaternary)
                    .aspectRatio(63.0 / 88.0, contentMode: .fit)
            }
        }
        .task(id: url) {
            image = nil
            if let url { image = await CardImages.shared.image(url) }
        }
    }
}

/// Card pictures, kept on disk (300 MB) so a card seen once shows offline too. Scryfall's image CDN
/// needs no rate limit; a picture is never rehosted, only cached on the phone.
final class CardImages: @unchecked Sendable {  // NSCache and URLSession are thread-safe
    static let shared = CardImages()
    private let session: URLSession
    private let memory = NSCache<NSURL, UIImage>()

    private init() {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 20_000_000, diskCapacity: 300_000_000,
                                   directory: URL.cachesDirectory.appending(path: "CardImages"))
        config.httpCookieStorage = nil
        session = URLSession(configuration: config)
        memory.countLimit = 60
    }

    func image(_ url: URL) async -> UIImage? {
        if let image = memory.object(forKey: url as NSURL) { return image }
        // the cached answer whenever there is one: a printing's picture doesn't change
        let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad)
        guard let answer = try? await session.data(for: request),
              let image = await UIImage(data: answer.0)?.byPreparingForDisplay() else { return nil }
        memory.setObject(image, forKey: url as NSURL)
        return image
    }
}

/// A card's outline: its corners are rounded by about 1/21 of its width, like a printed card (3 mm of
/// 63 mm), at any size. Scryfall's JPEGs have square corners with the border colour in them.
struct CardShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path(roundedRect: rect, cornerRadius: rect.width * 3 / 63, style: .continuous)
    }
}
