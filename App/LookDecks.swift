import ConclaveCore
import SwiftUI

/// One heading of the Decks tab with its decks: Pinned, Decks, Paused.
struct DeckGroup: Identifiable {
    var id: String { title }
    let title: String
    let decks: [Deck]
}

/// The Decks tab in the gallery and glass looks: tiles instead of list rows. On the iPad they
/// fill several columns.
struct DeckTiles: View {
    let groups: [DeckGroup]
    @Environment(\.look) private var look

    var body: some View {
        ScrollView {
            GlassEffectContainer(spacing: 16) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 16)], alignment: .leading, spacing: 16) {
                    ForEach(groups) { group in
                        Section {
                            ForEach(group.decks) { deck in
                                NavigationLink(value: deck.slug) {
                                    if look == .glass { GlassDeckTile(deck: deck) } else { GalleryDeckTile(deck: deck) }
                                }
                                .buttonStyle(.plain)
                            }
                        } header: {
                            LookHeader(group.title)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 12)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
        }
        .background {
            if look == .glass, let first = groups.first?.decks.first?.commanders.first {
                ArtBackdrop(name: first)
            }
        }
    }
}

/// A deck as a picture: the commander's art with the name on a dark fade at the bottom.
struct GalleryDeckTile: View {
    let deck: Deck

    var body: some View {
        CardArt(name: deck.commanders.first ?? "")
            .frame(height: 180)
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(deck.name)
                        .font(.title3.bold())
                        .lineLimit(1)
                    Text(deck.commanders.joined(separator: " + "))
                        .font(.subheadline)
                        .lineLimit(1)
                        .opacity(0.85)
                    DeckFacts(deck: deck)
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(.white)
                .padding(14)
                .padding(.top, 30)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .top, endPoint: .bottom))
            }
            .overlay(alignment: .topTrailing) { DeckBadges(deck: deck).padding(10) }
            .clipShape(.rect(cornerRadius: 20))
            .contentShape(.rect(cornerRadius: 20))
            .accessibilityElement(children: .combine)
    }
}

/// A deck on a glass panel: the commander's art in a circle, the name and facts beside it.
struct GlassDeckTile: View {
    let deck: Deck

    var body: some View {
        HStack(spacing: 14) {
            CardArt(name: deck.commanders.first ?? "")
                .frame(width: 64, height: 64)
                .clipShape(.circle)
            VStack(alignment: .leading, spacing: 4) {
                Text(deck.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(deck.commanders.joined(separator: " + "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                DeckFacts(deck: deck)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            DeckBadges(deck: deck)
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

/// A deck row in the brand look: a square of art, the name, the commander in monospace and chips.
struct BrandDeckRow: View {
    let deck: Deck

    var body: some View {
        HStack(spacing: 12) {
            CardArt(name: deck.commanders.first ?? "")
                .frame(width: 56, height: 56)
                .clipShape(.rect(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 4) {
                Text(deck.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(deck.commanders.joined(separator: " + "))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    ColorPips(colors: deck.colors)
                    if let bracket = deck.bracket { Chip(text: "B\(bracket)") }
                    if deck.record.games > 0 {
                        Text(recordText(wins: deck.record.wins, losses: deck.record.losses, draws: deck.record.draws))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    if deck.legal == false {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .accessibilityLabel("Not legal")
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// Colours, level and record in one line.
struct DeckFacts: View {
    let deck: Deck

    var body: some View {
        HStack(spacing: 8) {
            ColorPips(colors: deck.colors)
            if let level = deck.shownLevel { Text(level) }
            if deck.record.games > 0 {
                Text(recordText(wins: deck.record.wins, losses: deck.record.losses, draws: deck.record.draws))
                    .monospacedDigit()
                    .accessibilityLabel("\(deck.record.wins) wins, \(deck.record.losses) losses")
            }
        }
    }
}

/// Small signs on a tile: not legal.
struct DeckBadges: View {
    let deck: Deck

    var body: some View {
        if deck.legal == false {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(.orange)
                .padding(6)
                .background(.ultraThinMaterial, in: .circle)
                .accessibilityLabel("Not legal")
        }
    }
}

/// The top of a deck's screen in the gallery, brand and glass looks: the commander's art (big in the
/// gallery, a band in glass, none in brand), the commanders to tap, the facts as pills and Rule 0.
struct DeckHeader: View {
    let deck: Deck
    let showCard: (String) -> Void
    let showRule0: () -> Void
    @Environment(\.look) private var look

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if look == .gallery {
                CardArt(name: deck.commanders.first ?? "")
                    .frame(height: 260)
                    .overlay(alignment: .bottomLeading) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(deck.name)
                                .font(.largeTitle.bold())
                                .lineLimit(2)
                                .minimumScaleFactor(0.7)
                            commanders
                        }
                        .foregroundStyle(.white)
                        .padding(16)
                        .padding(.top, 40)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom))
                    }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text(deck.name)
                        .font(look == .brand ? .title.bold() : .largeTitle.bold())
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                    commanders
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    ColorPips(colors: deck.colors)
                    if let bracket = deck.bracket { Chip(text: "Bracket \(bracket)") }
                    if deck.proxy { Chip(text: "Proxy") }
                    if deck.legal == false { Chip(text: "Not legal") }
                }
                if let description = deck.description, !description.isEmpty {
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        StatPill(label: "Games", value: "\(deck.record.games)")
                        StatPill(label: "Won – lost", value: deck.record.games == 0 ? "–" : recordText(wins: deck.record.wins, losses: deck.record.losses, draws: deck.record.draws))
                        StatPill(label: "Speed", value: deck.speed?.shownLabel ?? "–")
                    }
                }
                rule0Button
                if deck.checking {
                    Label("Your PC checks the newest changes next time it syncs.", systemImage: "clock")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    /// Each commander as a button that opens its card.
    private var commanders: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(deck.commanders, id: \.self) { commander in
                Button {
                    showCard(commander)
                } label: {
                    HStack(spacing: 4) {
                        Text(commander)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .opacity(0.6)
                    }
                    .font(look == .brand ? .subheadline.monospaced() : .headline)
                }
                .buttonStyle(.plain)
                .foregroundStyle(look == .gallery ? Color.white : look == .brand ? Color.accentColor : Color.primary)
                .accessibilityHint("Shows the card")
            }
        }
    }

    @ViewBuilder
    private var rule0Button: some View {
        switch look {
        case .brand:
            Button(action: showRule0) {
                Label("Rule 0", systemImage: "text.bubble")
                    .font(.headline.monospaced())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundStyle(.black)
                    .background(Color("Neon"), in: .rect(cornerRadius: 6))
            }
            .buttonStyle(.plain)
        case .glass:
            Button(action: showRule0) {
                Label("Rule 0", systemImage: "text.bubble")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glass)
        default:
            Button(action: showRule0) {
                Label("Rule 0", systemImage: "text.bubble")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color("Neon"))
            .foregroundStyle(.black)
        }
    }
}
