import ConclaveCore
import SwiftUI
import UIKit

// The app's look, picked by Flo from four variants (draft PR #14): Liquid Glass panels floating
// over a commander's blurred art. These are the pieces the screens share.

/// A card's art crop (Scryfall's `art_crop`), filling whatever frame it gets. A quiet grey shows
/// while it loads or when there is no art.
struct CardArt: View {
    let name: String
    @Environment(AppModel.self) private var model
    @State private var image: UIImage?

    var body: some View {
        Rectangle()
            .fill(.quaternary)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                }
            }
            .clipped()
            .accessibilityHidden(true)
            .task(id: name) {
                guard !name.isEmpty else { return }
                let card = try? await model.cards.card(named: name)
                guard let url = card?.art else { return }
                let loaded = await CardImages.shared.image(url)
                withAnimation(.easeOut(duration: 0.25)) { image = loaded }
            }
    }
}

/// A commander's art blurred behind the whole screen, toned down towards the background colour
/// so text on glass stays readable in light and dark mode.
struct ArtBackdrop: View {
    let name: String

    var body: some View {
        CardArt(name: name)
            .blur(radius: 50)
            .overlay(.background.opacity(0.45))
            .ignoresSafeArea()
    }
}

/// A small outlined label in a capsule: the bracket, "Proxy", "Not legal".
struct Chip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(Color.accentColor)
            .background(Capsule().strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 1))
    }
}

/// One number with its label on a small glass panel, used in the deck screen's header.
struct StatPill: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}

/// Tiles in a grid over a card's blurred art: one column on the iPhone, several on the iPad.
struct TileGrid<Content: View>: View {
    /// The card whose art lies behind the tiles.
    let backdrop: String?
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            GlassEffectContainer(spacing: 16) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 16)], alignment: .leading, spacing: 16) {
                    content
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background {
            if let backdrop { ArtBackdrop(name: backdrop) }
        }
    }
}

/// A glass panel for one deck or opponent: the commander's art in a circle, a title, a subtitle
/// and a line of facts, a warning sign when needed, and a chevron.
struct GlassTile<Facts: View>: View {
    let art: String
    let title: String
    var subtitle: String?
    /// Shown as an orange sign, spoken by VoiceOver ("Not legal").
    var warning: String?
    @ViewBuilder let facts: Facts

    var body: some View {
        HStack(spacing: 14) {
            CardArt(name: art)
                .frame(width: 64, height: 64)
                .clipShape(.circle)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                HStack(spacing: 8) { facts }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if let warning {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityLabel(warning)
            }
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 24))
        .contentShape(.rect(cornerRadius: 24))
        .accessibilityElement(children: .combine)
    }
}

/// A section heading over the art: bigger and bolder than a list's, so it holds its own on glass.
struct GlassHeader: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.title3.bold())
            .foregroundStyle(.primary)
            .textCase(nil)
    }
}

extension View {
    /// A list whose rows sit on frosted panels over a commander's art.
    func glassList(over commander: String) -> some View {
        scrollContentBackground(.hidden)
            .background { ArtBackdrop(name: commander) }
    }

    /// One row of a `glassList`.
    func glassRow() -> some View {
        listRowBackground(Rectangle().fill(.ultraThinMaterial))
    }
}
