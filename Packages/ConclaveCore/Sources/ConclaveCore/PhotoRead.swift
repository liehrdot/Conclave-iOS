import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// "Take Photo": a still photo read as a whole, for cards the live picture can't get. Mirrors `scanPhoto()`
/// in `scan.js`: the same reader, tried with card frames of a few sizes around the middle, the best hit wins.
public enum PhotoRead {
    /// Where a box in the photo (pixels from the top left) shows on the screen, which fills itself with the
    /// photo like the camera preview does (aspect fill, centred), so the card frame can be laid over it.
    public static func screenRect(of box: CGRect, photo: CGSize, screen: CGSize) -> CGRect {
        let pw = Double(photo.width), ph = Double(photo.height), sw = Double(screen.width), sh = Double(screen.height)
        guard pw > 0, ph > 0 else { return .zero }
        let scale = max(sw / pw, sh / ph)
        let dx = (sw - pw * scale) / 2, dy = (sh - ph * scale) / 2
        return CGRect(x: Double(box.minX) * scale + dx, y: Double(box.minY) * scale + dy,
                      width: Double(box.width) * scale, height: Double(box.height) * scale)
    }

    /// The card frames to try: the one on the screen first, then smaller and larger ones around its middle
    /// (`PHOTO_SIZES` in `scan.js`), as a card is rarely held exactly in the frame for a photo.
    public static func frames(around frame: CGRect) -> [CGRect] {
        [1, 0.85, 1.15, 0.7].map { f in
            let w = Double(frame.width) * f, h = Double(frame.height) * f
            return CGRect(x: Double(frame.midX) - w / 2, y: Double(frame.midY) - h / 2, width: w, height: h)
        }
    }

    /// The card a photo shows: its read lines (text and box in the photo, from the top left) laid over each
    /// of `frames(around:)` on the screen and read like a camera frame; the best hit wins. Stops early when the
    /// set line and the name agree. The app's "Take Photo" and the scanner benchmark both go through here.
    public static func identify(_ lines: [(text: String, box: CGRect)], photo: CGSize, screen: CGSize, frame: CGRect,
                                reader: CardReader) async -> ReadHit? {
        var hits: [ReadHit] = []
        for frame in frames(around: frame) {
            let placed = lines.map { line in
                let box = screenRect(of: line.box, photo: photo, screen: screen)
                let corners = [CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.maxX, y: box.minY),
                               CGPoint(x: box.maxX, y: box.maxY), CGPoint(x: box.minX, y: box.maxY)]
                return ReadLine(line.text, points: corners, frame: frame)
            }
            guard let hit = await reader.identify(CardRead(placed)) else { continue }
            hits.append(hit)
            if hit.bySet && !hit.read.isEmpty { break } // set line and name agree: nothing better to find
        }
        return best(hits)
    }

    /// The best of several reads' hits: the set line and the name agree › the whole name read › a piece of it
    /// (`coverage()` in `scan.js`).
    public static func best(_ hits: [ReadHit]) -> ReadHit? {
        func rank(_ hit: ReadHit) -> Int {
            if hit.bySet && !hit.read.isEmpty { return 3 }
            if hit.sure { return 2 }
            return hit.read.isEmpty ? 0 : 1
        }
        return hits.enumerated().max { (rank($0.element), -$0.offset) < (rank($1.element), -$1.offset) }?.element
    }
}
