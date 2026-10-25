import AVFoundation
import ConclaveCore
import SwiftUI
import UIKit

/// Text with its mana symbols drawn like on the cards: "{T}: Add {G}." shows the tap symbol and a
/// green mana symbol inside the line, at the text's size (they grow with Dynamic Type). VoiceOver
/// reads the symbols by name. Mirrors `mana()` / `rulesText()` in the PWA's `util.js`.
struct ManaText: View {
    let text: String
    let style: Font.TextStyle
    @ScaledMetric private var size: CGFloat

    init(_ text: String, style: Font.TextStyle = .body) {
        self.text = text
        self.style = style
        _size = ScaledMetric(wrappedValue: Self.baseSize(style), relativeTo: style)
    }

    var body: some View {
        line
            .font(.system(style))
            .accessibilityLabel(Mana.spoken(text))
    }

    private var line: Text {
        var out = Text(verbatim: "")
        var lastWasSymbol = false
        for piece in Mana.pieces(text) {
            switch piece {
            case .text(let plain):
                out = Text("\(out)\(Text(verbatim: plain))")
                lastWasSymbol = false
            case .symbol(let symbol):
                // a hair space between symbols in a row, like the printed costs
                let gap = lastWasSymbol ? Text(verbatim: "\u{200A}") : Text(verbatim: "")
                let image = Text(Image(uiImage: ManaGlyphs.image(symbol, size: size)).renderingMode(.original)).baselineOffset(-size * 0.16)
                out = Text("\(out)\(gap)\(image)")
                lastWasSymbol = true
            }
        }
        return out
    }

    /// About the text style's cap-to-descender height, so a symbol sits in the line like a capital.
    private static func baseSize(_ style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: 30
        case .title: 25
        case .title2: 20
        case .title3: 18
        case .headline, .body: 15
        case .callout: 14
        case .subheadline: 13
        case .footnote: 12
        default: 11
        }
    }
}

/// The symbols as small pictures: a coloured circle with the symbol's glyph from the Mana font (OFL,
/// App/Resources/Mana-LICENSE.txt), a number for generic mana, split circles for hybrid mana. Drawn
/// once per symbol and size.
@MainActor
enum ManaGlyphs {
    private static var drawn: [String: UIImage] = [:]

    /// The circles' colours, the same as the PWA's `--ms-*`.
    static let fills: [String: UIColor] = [
        "W": UIColor(red: 1.00, green: 0.98, blue: 0.84, alpha: 1), "U": UIColor(red: 0.67, green: 0.88, blue: 0.98, alpha: 1),
        "B": UIColor(red: 0.80, green: 0.76, blue: 0.75, alpha: 1), "R": UIColor(red: 0.98, green: 0.67, blue: 0.56, alpha: 1),
        "G": UIColor(red: 0.61, green: 0.83, blue: 0.68, alpha: 1),
    ]
    static let grey = UIColor(red: 0.80, green: 0.76, blue: 0.75, alpha: 1)

    static func image(_ symbol: Mana.Symbol, size: CGFloat) -> UIImage {
        let key = "\(symbol.raw.uppercased())@\(Int(size * 4))"
        if let image = drawn[key] { return image }
        let rect = CGRect(x: 0, y: 0, width: size, height: size)
        let image = UIGraphicsImageRenderer(size: rect.size).image { context in
            let cg = context.cgContext
            func circle(_ color: UIColor) {
                color.setFill()
                cg.fillEllipse(in: rect)
            }
            switch symbol.kind {
            case .color(let c):
                circle(fills[c] ?? grey)
                glyph(c, in: rect.insetBy(dx: size * 0.13, dy: size * 0.13))
            case .glyph(let g):
                circle(g == "Q" ? .black : grey)
                glyph(g, in: rect.insetBy(dx: size * 0.1, dy: size * 0.1), color: g == "Q" ? .white : .black)
            case .phyrexian(let c):
                circle(fills[c] ?? grey)
                glyph("P", in: rect.insetBy(dx: size * 0.13, dy: size * 0.13))
            case .generic(let text):
                circle(grey)
                number(text, in: rect.insetBy(dx: size * 0.1, dy: size * 0.1), size: size * 0.72)
            case .hybrid(let a, let b):
                // split along the falling diagonal: the first half top left, the second bottom right
                cg.saveGState()
                cg.addEllipse(in: rect)
                cg.clip()
                (fills[a] ?? grey).setFill()
                cg.fill(rect)
                let lower = UIBezierPath()
                lower.move(to: CGPoint(x: size, y: 0))
                lower.addLine(to: CGPoint(x: size, y: size))
                lower.addLine(to: CGPoint(x: 0, y: size))
                lower.close()
                (fills[b] ?? grey).setFill()
                lower.fill()
                cg.restoreGState()
                let side = size * 0.46
                half(a, in: CGRect(x: size * 0.08, y: size * 0.08, width: side, height: side))
                half(b, in: CGRect(x: size * 0.46, y: size * 0.46, width: side, height: side))
            }
        }
        drawn[key] = image
        return image
    }

    /// One half of a hybrid symbol: a colour's glyph or a number.
    private static func half(_ part: String, in rect: CGRect) {
        if part.count == 1, "WUBRGC".contains(part) { glyph(part, in: rect) } else { number(part, in: rect, size: rect.height) }
    }

    private static func glyph(_ name: String, in rect: CGRect, color: UIColor = .black) {
        guard let image = UIImage(named: "mana-\(name)") else { return }
        let fit = AVMakeRect(aspectRatio: image.size, insideRect: rect)
        image.withTintColor(color, renderingMode: .alwaysOriginal).draw(in: fit)
    }

    private static func number(_ text: String, in rect: CGRect, size: CGFloat) {
        var font = UIFont.systemFont(ofSize: size, weight: .semibold)
        var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.black]
        var measured = (text as NSString).size(withAttributes: attributes)
        if measured.width > rect.width {  // "10", "CHAOS": smaller until it fits
            font = font.withSize(size * rect.width / measured.width)
            attributes[.font] = font
            measured = (text as NSString).size(withAttributes: attributes)
        }
        let origin = CGPoint(x: rect.midX - measured.width / 2, y: rect.midY - measured.height / 2)
        (text as NSString).draw(at: origin, withAttributes: attributes)
    }
}
