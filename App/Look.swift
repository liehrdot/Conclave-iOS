import ConclaveCore
import SwiftUI
import UIKit

// The app's look: a commander's blurred art behind the screen (Flo's pick from draft PR #14), with the
// content on standard materials. Liquid Glass stays where Apple puts it, on the bars and controls that
// float above the content: "Don't use Liquid Glass in the content layer" (HIG, Materials). Flo chose
// this on 2026-10-26 after the deep dive into Apple's guidelines.
// These are the pieces the screens share.

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
/// so text on the material stays readable in light and dark mode.
struct ArtBackdrop: View {
    let name: String

    var body: some View {
        CardArt(name: name)
            .blur(radius: 50)
            .overlay(.background.opacity(0.45))
            .ignoresSafeArea()
    }
}

/// A small label in a capsule on the regular material, coloured only where the colour means something:
/// a bracket carries a dot that gets warmer as the deck gets stronger, a problem ("Not legal") a red sign,
/// anything else ("Proxy") is plain. The words always say it too, so colour is never the only signal
/// (HIG, Accessibility).
struct Chip: View {
    enum Kind {
        case plain
        case bracket(Int)
        case problem
    }

    let text: String
    var kind: Kind = .plain

    /// "Bracket 3" with its dot.
    static func bracket(_ bracket: Int) -> Chip { Chip(text: "Bracket \(bracket)", kind: .bracket(bracket)) }

    var body: some View {
        HStack(spacing: 5) {
            switch kind {
            case .plain:
                EmptyView()
            case let .bracket(bracket):
                Circle()
                    .fill(Self.tone(bracket))
                    .frame(width: 8, height: 8)
            case .problem:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
            Text(text)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.primary)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(.regularMaterial, in: .capsule)
    }

    /// Bracket 1 blue, 2 green, 3 yellow, 4 orange, 5 red: the dot's colour. System colours, so they
    /// adapt to dark mode and Increase Contrast (HIG, Color).
    static func tone(_ bracket: Int) -> Color {
        switch bracket {
        case ...1: .blue
        case 2: .green
        case 3: .yellow
        case 4: .orange
        default: .red
        }
    }
}

/// One number with its label on a small panel, used in the deck and opponent headers.
struct StatPill: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline)
                .monospacedDigit()
                .multilineTextAlignment(.center)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
        .background(.regularMaterial, in: .rect(cornerRadius: 16))
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
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 16)], alignment: .leading, spacing: 16) {
                content
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background {
            if let backdrop { ArtBackdrop(name: backdrop) }
        }
    }
}

/// A panel for one deck or opponent: the commander's art in a circle, a title, a subtitle and a line
/// of facts, a warning sign when needed, and a chevron. A tile is content, so it sits on the regular
/// material, not on Liquid Glass (HIG, Materials).
struct ArtTile<Facts: View>: View {
    let art: String
    let title: String
    var subtitle: String?
    /// Shown as a red sign, spoken by VoiceOver ("Not legal"), the same red as a problem `Chip`.
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
                    .foregroundStyle(.red)
                    .accessibilityLabel(warning)
            }
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: .rect(cornerRadius: 24))
        .contentShape(.rect(cornerRadius: 24))
        .accessibilityElement(children: .combine)
    }
}

/// A section heading over the art: bigger and bolder than a list's, so it holds its own over the
/// picture behind it.
struct SectionTitle: View {
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
    /// A list whose rows sit on the regular material over a commander's art.
    func artList(over commander: String) -> some View {
        scrollContentBackground(.hidden)
            .background { ArtBackdrop(name: commander) }
    }

    /// One row of an `artList`: the regular material, thick enough to keep text readable over any art
    /// ("Thicker materials … can provide better contrast for text", HIG, Materials).
    func materialRow() -> some View {
        listRowBackground(Rectangle().fill(.regularMaterial))
    }
}
