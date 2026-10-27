import ConclaveCore
import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

// swift run -c release ScanBench [count] [--from cards.txt] [--out dir]
// count: random cards to ask Scryfall for (default 60, about one in five German); --from: "set/number/lang" lines of
// an earlier run's cards.txt, to measure a change on the same cards.

/// The card as Scryfall knows it, only what the benchmark needs.
struct Picked: Decodable {
    struct Images: Decodable { var png: URL? }
    struct Face: Decodable { var oracle_id: String?; var image_uris: Images? }
    var id: String
    var oracle_id: String?
    var name: String
    var printed_name: String?
    var lang: String
    var set: String
    var collector_number: String
    var image_uris: Images?
    var card_faces: [Face]?

    var oracle: String { oracle_id ?? card_faces?.first?.oracle_id ?? "" }
    var image: URL? { image_uris?.png ?? card_faces?.first?.image_uris?.png }
    var key: String { "\(set)/\(collector_number)/\(lang)" }
    var shown: String { printed_name.map { "\($0) (\(name))" } ?? name }
}

let session = URLSession(configuration: .ephemeral)
var lastAsk = ContinuousClock.now - .seconds(1)

/// Scryfall asks for 50–100 ms between requests, and the two headers.
@MainActor func get(_ url: URL) async throws -> Data {
    let wait = lastAsk + .milliseconds(120) - ContinuousClock.now
    if wait > .zero { try await Task.sleep(for: wait) }
    lastAsk = ContinuousClock.now
    var request = URLRequest(url: url)
    request.setValue("ConclaveScanBench/1.0", forHTTPHeaderField: "User-Agent")
    request.setValue("application/json;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
    let (data, response) = try await session.data(for: request)
    guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
    return data
}

func randomCard(german: Bool) async throws -> Picked {
    // paper cards a collection holds: no tokens, emblems, art cards or digital-only ones
    let q = "game:paper -is:digital -layout:token -layout:double_faced_token -layout:emblem -layout:art_series -is:funny lang:"
        + (german ? "de" : "en")
    var parts = URLComponents(string: "https://api.scryfall.com/cards/random")!
    parts.queryItems = [URLQueryItem(name: "q", value: q)]
    return try JSONDecoder().decode(Picked.self, from: try await get(parts.url!))
}

func card(_ key: String) async throws -> Picked {
    let p = key.split(separator: "/").map(String.init)
    return try JSONDecoder().decode(Picked.self, from: try await get(URL(string: "https://api.scryfall.com/cards/\(p[0])/\(p[1])/\(p[2])")!))
}

// MARK: - The made-up photo

/// A seeded random number per card, so the same card always gets the same photo.
struct Dice {
    var state: UInt64
    init(_ text: String) { state = text.utf8.reduce(1469598103934665603) { ($0 ^ UInt64($1)) &* 1099511628211 } }
    mutating func next(_ range: ClosedRange<Double>) -> Double {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        z ^= z >> 31
        return range.lowerBound + Double(z % 1_000_000) / 1_000_000 * (range.upperBound - range.lowerBound)
    }
}

/// An iPhone 17 Pro's screen in points and the scan screen's card frame on it (lens buttons shown), and the photo the
/// camera takes: 3:4, aspect-filling the screen like the preview.
let screen = CGSize(width: 402, height: 874)
let frame = CardFrame.rect(in: screen, top: 62 + 12, bottom: 34 + 182)
let photoSize = CGSize(width: 1512, height: 2016)

/// The screen rect in the photo (the reverse of `PhotoRead.screenRect`).
func inPhoto(_ rect: CGRect) -> CGRect {
    let scale = max(screen.width / photoSize.width, screen.height / photoSize.height)
    let dx = (screen.width - photoSize.width * scale) / 2, dy = (screen.height - photoSize.height * scale) / 2
    return CGRect(x: (rect.minX - dx) / scale, y: (rect.minY - dy) / scale, width: rect.width / scale, height: rect.height / scale)
}

let context = CIContext()

/// The card held a little off, turned, out of focus and in other light, on a table.
func photo(of picture: CGImage, seed: String) -> CGImage? {
    var dice = Dice(seed)
    let size = dice.next(0.86...1.0), turn = dice.next(-3...3) * .pi / 180
    let shiftX = dice.next(-0.03...0.03), shiftY = dice.next(-0.03...0.03)
    let blur = dice.next(0...2.2), light = dice.next(-0.5...0.3)
    let table = dice.next(0.15...0.55)

    let width = Int(photoSize.width), height = Int(photoSize.height)
    guard let canvas = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                 space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    canvas.setFillColor(CGColor(red: table, green: table * 0.9, blue: table * 0.8, alpha: 1))
    canvas.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let target = inPhoto(frame)
    let w = target.width * size, h = target.height * size
    let mid = CGPoint(x: target.midX + target.width * shiftX, y: target.midY + target.height * shiftY)
    // Core Graphics counts from the bottom
    canvas.translateBy(x: mid.x, y: CGFloat(height) - mid.y)
    canvas.rotate(by: turn)
    canvas.draw(picture, in: CGRect(x: -w / 2, y: -h / 2, width: w, height: h))
    guard let drawn = canvas.makeImage() else { return nil }

    var image = CIImage(cgImage: drawn)
    image = image.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: light])
    if blur > 0.2 { image = image.clampedToExtent().applyingGaussianBlur(sigma: blur).cropped(to: CGRect(x: 0, y: 0, width: width, height: height)) }
    let noise = CIFilter(name: "CIRandomGenerator")!.outputImage!.cropped(to: image.extent)
        .applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0.06)])
    image = noise.composited(over: image)
    return context.createCGImage(image, from: CGRect(x: 0, y: 0, width: width, height: height))
}

/// Vision on the photo, as the app's `PhotoText.read` does it.
func readText(_ image: CGImage) async -> [(text: String, box: CGRect)] {
    var request = RecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = false
    request.recognitionLanguages = ["en-US", "de-DE", "fr-FR", "it-IT", "es-ES", "pt-BR"].map { Locale.Language(identifier: $0) }
    guard let found = try? await request.perform(on: image) else { return [] }
    return found.compactMap { o in
        o.topCandidates(1).first.map { ($0.string, o.boundingBox.toImageCoordinates(photoSize, origin: .upperLeft)) }
    }
}

func save(_ image: CGImage, to url: URL) {
    guard let out = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return }
    CGImageDestinationAddImage(out, image, [kCGImageDestinationLossyCompressionQuality: 0.7] as CFDictionary)
    CGImageDestinationFinalize(out)
}

// MARK: - The run

var args = Array(CommandLine.arguments.dropFirst())
@MainActor func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    defer { args.removeSubrange(i...(i + 1)) }
    return args[i + 1]
}
let from = option("--from")
let outDir = URL(fileURLWithPath: option("--out") ?? "scanbench-out")
let count = args.first.flatMap(Int.init) ?? 60
try? FileManager.default.createDirectory(at: outDir.appendingPathComponent("misses"), withIntermediateDirectories: true)

var cards: [Picked] = []
if let from {
    for key in try String(contentsOfFile: from, encoding: .utf8).split(separator: "\n") where !key.isEmpty {
        if let c = try? await card(String(key)) { cards.append(c) }
    }
} else {
    for i in 0..<count {
        if let c = try? await randomCard(german: i % 5 == 4) { cards.append(c) }
    }
}
try cards.map(\.key).joined(separator: "\n").write(to: outDir.appendingPathComponent("cards.txt"), atomically: true, encoding: .utf8)

let reader = CardReader(lookup: Scryfall(transport: URLSession.conclave()))
var photoRight = 0, photoExact = 0, frameRight = 0, wrong = 0
var rows: [String] = []

for (n, c) in cards.enumerated() {
    guard let url = c.image, let data = try? await get(url),
          let source = CGImageSourceCreateWithData(data as CFData, nil),
          let picture = CGImageSourceCreateImageAtIndex(source, 0, nil),
          let scene = photo(of: picture, seed: c.id)
    else { rows.append("| \(n + 1) | \(c.shown) | \(c.key) | no picture | | |"); continue }

    let lines = await readText(scene)
    // "Take Photo": several frames, the best hit
    let hit = await PhotoRead.identify(lines, photo: photoSize, screen: screen, frame: frame, reader: reader)
    // the live scanner's view: one read over the frame as it is (the app needs it sure, or twice)
    let placed = lines.map { l -> ReadLine in
        let b = PhotoRead.screenRect(of: l.box, photo: photoSize, screen: screen)
        return ReadLine(l.text, points: [CGPoint(x: b.minX, y: b.minY), CGPoint(x: b.maxX, y: b.minY),
                                         CGPoint(x: b.maxX, y: b.maxY), CGPoint(x: b.minX, y: b.maxY)], frame: frame)
    }
    let read = CardRead(placed)
    let live = await reader.identify(read)

    let right = hit?.printing.oracleID == c.oracle
    let exact = right && hit?.printing.set == c.set && hit?.printing.collectorNumber == c.collector_number
    if right { photoRight += 1 } else if hit != nil { wrong += 1 }
    if exact { photoExact += 1 }
    if live?.printing.oracleID == c.oracle && live?.sure == true { frameRight += 1 }

    let got = hit.map { "\($0.printing.name) \($0.printing.set.uppercased()) #\($0.printing.collectorNumber)" } ?? "nothing"
    let mark = exact ? "✅" : right ? "☑️ other printing" : hit == nil ? "⬜ none" : "❌ wrong"
    let seen = (read.names.first ?? "–") + " · " + (read.line.map { "\($0.set.uppercased()) #\($0.number) \($0.lang)" } ?? "no set line")
    rows.append("| \(n + 1) | \(c.shown) | \(c.key) | \(mark) | \(got) | \(seen.replacingOccurrences(of: "|", with: "/")) |")
    if !exact { save(scene, to: outDir.appendingPathComponent("misses/\(n + 1)-\(c.set)-\(c.collector_number)-\(c.lang).jpg")) }
    print("\(n + 1)/\(cards.count) \(mark) \(c.shown) → \(got)")
}

let total = max(cards.count, 1)
@MainActor func pct(_ n: Int) -> String { String(format: "%d/%d (%.0f %%)", n, cards.count, Double(n) * 100 / Double(total)) }
let summary = """
## Scanner benchmark

\(cards.count) random cards from Scryfall (about one in five German), each in a made-up camera photo.

| | |
|---|---|
| **Take Photo: right card** | \(pct(photoRight)) |
| Take Photo: exact printing | \(pct(photoExact)) |
| Take Photo: wrong card | \(pct(wrong)) |
| Live frame alone, sure at once | \(pct(frameRight)) |

The web app's benchmark: 45/50 live, 47/50 by photo.

| # | Card | Set/number/lang | Result | Found | Read (name · set line) |
|---|---|---|---|---|---|
\(rows.joined(separator: "\n"))
"""
print(summary)
try summary.write(to: outDir.appendingPathComponent("summary.md"), atomically: true, encoding: .utf8)
if let path = ProcessInfo.processInfo.environment["GITHUB_STEP_SUMMARY"] {
    if let handle = FileHandle(forWritingAtPath: path) {
        handle.seekToEndOfFile()
        handle.write(Data(summary.utf8))
        handle.closeFile()
    }
}
