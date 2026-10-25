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
