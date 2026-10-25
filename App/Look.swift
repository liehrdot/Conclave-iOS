import ConclaveCore
import SwiftUI
import UIKit

/// Look-and-feel variants for Flo to compare before Milestone 2. This is a draft and never gets merged.
/// The winner gets built cleanly in its own PR. Each variant is a different approach to the Decks tab:
/// - `today`: the app as it is now.
/// - `gallery`: big commander art, like Apple Music or Flighty.
/// - `brand`: the flat neon look of Conclave on the PC and the web app.
/// - `glass`: iOS 26 Liquid Glass panels over the commander's art.
///
/// The look is picked in Settings › Look and saved in UserDefaults `look`.
/// The screenshots pick it with the environment variable `CONCLAVE_LOOK`, which is not saved.
enum Look: String, CaseIterable, Identifiable {
    case today, gallery, brand, glass

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "Today"
        case .gallery: "Gallery"
        case .brand: "Conclave"
        case .glass: "Glass"
        }
    }

    var blurb: String {
        switch self {
        case .today: "Plain iOS lists, as the app is now."
        case .gallery: "Big commander art on every deck, like Apple Music."
        case .brand: "The flat neon look of Conclave on your PC."
        case .glass: "Liquid Glass panels over the commander's art."
        }
    }

    static let key = "look"
    /// The screenshots' pick: wins over the saved one and is never saved itself.
    static let launchChoice = ProcessInfo.processInfo.environment["CONCLAVE_LOOK"].flatMap(Look.init(rawValue:))
}

extension EnvironmentValues {
    @Entry var look: Look = .today
}

extension Color {
    /// One colour for light mode, one for dark.
    static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }

    /// The brand look's background: the desktop's neutral greys.
    static let brandBackground = dynamic(
        light: UIColor(red: 0.96, green: 0.96, blue: 0.95, alpha: 1),
        dark: UIColor(red: 0.05, green: 0.06, blue: 0.05, alpha: 1))
    /// Hairlines between rows instead of grouped boxes.
    static let hairline = Color.primary.opacity(0.12)
}

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

/// A deck's commander art blurred behind the whole screen: the glass look's backdrop.
struct ArtBackdrop: View {
    let name: String

    var body: some View {
        CardArt(name: name)
            .blur(radius: 50)
            .overlay(.background.opacity(0.45))
            .ignoresSafeArea()
    }
}

/// A small label in a capsule: the bracket, "Proxy", "Paused".
struct Chip: View {
    let text: String
    var filled = false
    @Environment(\.look) private var look

    var body: some View {
        Text(text)
            .font(look == .brand ? .caption.monospaced().weight(.semibold) : .caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(filled ? Color.black : Color.accentColor)
            .background {
                if filled {
                    Capsule().fill(Color("Neon"))
                } else {
                    Capsule().strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 1)
                }
            }
    }
}

/// One number with its label, used in the deck screen's header.
struct StatPill: View {
    let label: String
    let value: String
    @Environment(\.look) private var look

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(look == .brand ? .headline.monospaced() : .headline)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(look == .brand ? label.uppercased() : label)
                .font(look == .brand ? .caption2.monospaced() : .caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background {
            switch look {
            case .brand: RoundedRectangle(cornerRadius: 6).strokeBorder(Color.hairline)
            case .glass: Color.clear
            default: RoundedRectangle(cornerRadius: 14).fill(.thinMaterial)
            }
        }
        .modifier(GlassIf(look == .glass, shape: .rect(cornerRadius: 16)))
        .accessibilityElement(children: .combine)
    }
}

/// Liquid Glass when on, nothing otherwise.
struct GlassIf<S: Shape>: ViewModifier {
    let on: Bool
    let shape: S
    var interactive = false

    init(_ on: Bool, shape: S, interactive: Bool = false) {
        self.on = on
        self.shape = shape
        self.interactive = interactive
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if on {
            content.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            content
        }
    }
}

/// A section header in the current look: the brand look's is small monospaced capitals.
struct LookHeader: View {
    let text: String
    @Environment(\.look) private var look

    init(_ text: String) { self.text = text }

    var body: some View {
        switch look {
        case .brand:
            Text(text.uppercased())
                .font(.caption.monospaced().weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(Color.accentColor)
        case .gallery, .glass:
            Text(text)
                .font(.title3.bold())
                .foregroundStyle(.primary)
                .textCase(nil)
        case .today:
            Text(text)
        }
    }
}

/// The list around a deck's cards, in the current look.
struct LookList: ViewModifier {
    let commander: String
    @Environment(\.look) private var look

    @ViewBuilder
    func body(content: Content) -> some View {
        switch look {
        case .today, .gallery:
            content
        case .brand:
            content
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Color.brandBackground)
        case .glass:
            content
                .scrollContentBackground(.hidden)
                .background { ArtBackdrop(name: commander) }
        }
    }
}

/// One row of a list in the current look.
struct LookRow: ViewModifier {
    @Environment(\.look) private var look

    @ViewBuilder
    func body(content: Content) -> some View {
        switch look {
        case .today, .gallery:
            content
        case .brand:
            content
                .listRowBackground(Color.clear)
                .listRowSeparatorTint(Color.hairline)
        case .glass:
            content
                .listRowBackground(Rectangle().fill(.ultraThinMaterial))
        }
    }
}
