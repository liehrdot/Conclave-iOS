import AVFoundation
import ConclaveCore
import SwiftUI
import Vision
import VisionKit

/// "Scan Cards": hold a card in the frame, the phone reads its name and set line and opens the add sheet.
/// Apple's live text scanner (VisionKit) reads; `CardReader` in the core turns the text into a printing,
/// like the web app's scanner (`scan.js`). The overlay shows what it reads while it reads: a faint box on
/// every line, the name and the set line labelled, and a status at the bottom.
struct CardScanView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// nil until the camera question is answered.
    @State private var allowed: Bool?
    @State private var seen = ScanSeen()
    @State private var status = ScanStatus.looking
    @State private var steadiness = ScanSteadiness()
    @State private var reader: CardReader?
    /// A read waiting while the reader is busy with the one before: only the newest counts.
    @State private var waiting: CardRead?
    @State private var busy = false
    /// The card the add sheet is open for; the camera pauses meanwhile.
    @State private var found: Printing?
    @State private var typing = false
    @State private var hits = 0
    /// "Add" was tapped in the add sheet, not "Cancel".
    @State private var added = false
    /// The lens buttons, from the back camera itself: VisionKit tells its zoom range only once it runs, and late.
    @State private var lenses: [Lens] = []
    /// The picked lens's zoom, kept for the next scan; 0 = the scanner's own start (the main camera).
    @AppStorage("scanZoom") private var zoom = 0.0
    @State private var torch = false
    private let camera = BackCamera()
    private let shutter = Shutter()
    /// A photo is being taken and read: the live picture's reads wait.
    @State private var snapping = false
    /// The screen and the card frame on it, for laying the photo's lines over the frame.
    @State private var layout = ScanLayout()

    private var running: Bool { found == nil && !typing }

    var body: some View {
        NavigationStack {
            GeometryReader { outer in
                let insets = outer.safeAreaInsets
                let screen = CGSize(width: outer.size.width + insets.leading + insets.trailing,
                                    height: outer.size.height + insets.top + insets.bottom)
                let frame = CardFrame.rect(in: screen, top: insets.top + 12, bottom: insets.bottom + (lenses.count > 1 ? 182 : 130))
                ZStack {
                    Color.black
                    if allowed == false || !DataScannerViewController.isSupported {
                        noCamera
                    } else if allowed == true {
                        if running {
                            // gone while a sheet is open: the camera turns off (its light too) instead of reading on
                            // behind the sheet, and comes back when the sheet closes, like `pause()` in `scan.js`
                            TextScanner(region: Self.region(around: frame), running: running, zoom: zoom > 0 ? zoom : nil,
                                        torch: torch, camera: camera, shutter: shutter) { read($0, frame: frame) }
                                .transition(.opacity)
                        }
                        ScanOverlay(frame: frame, seen: seen, status: status)
                    }
                }
                .ignoresSafeArea()
                .onChange(of: ScanLayout(screen: screen, frame: frame), initial: true) { _, now in layout = now }
            }
            .overlay(alignment: .bottom) { bottomBar }
            .environment(\.colorScheme, .dark) // a camera screen is dark in light mode too
            .navigationTitle("Scan Cards")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                if allowed == true, camera.hasTorch {
                    // like the flashlight in Control Center: for dim tables and dark card frames
                    ToolbarItem(placement: .primaryAction) {
                        Button(torch ? "Turn Flashlight Off" : "Turn Flashlight On",
                               systemImage: torch ? "flashlight.on.fill" : "flashlight.off.fill") { torch.toggle() }
                            .labelStyle(.iconOnly)
                            .sensoryFeedback(.selection, trigger: torch)
                    }
                }
            }
            .task {
                reader = CardReader(lookup: model.cards.scryfall)
                guard DataScannerViewController.isSupported else { return } // no question without a scanner
                allowed = await AVCaptureDevice.requestAccess(for: .video)
                lenses = Lens.choices(switchOvers: camera.switchOvers, ultraWide: camera.ultraWide, max: camera.maxZoom)
            }
            .sensoryFeedback(.success, trigger: hits)
            .onChange(of: running) { _, now in
                guard !now else { return }
                seen = ScanSeen() // no boxes left over from before the pause
                waiting = nil
            }
            .sheet(item: $found, onDismiss: { if !added { status = .looking } }) { printing in
                AddToCollectionView(name: printing.name, printing: printing) { card in
                    added = true
                    status = .added(card.shownName)
                }
            }
            .sheet(isPresented: $typing) { AddByNameView() }
        }
    }

    /// The status and "Type a Name", floating over the camera (glass belongs on that layer).
    private var bottomBar: some View {
        VStack(spacing: 12) {
            if allowed == true, lenses.count > 1 { lensPicker }
            if allowed == true {
                Label(status.text, systemImage: status.symbol)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .contentTransition(.identity) // the words swap at once; a cross-fade of two sentences overlaps
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .glassEffect(.regular.tint(status.isFound ? Color.accentColor.opacity(0.5) : nil), in: .capsule)
                    .accessibilityAddTraits(.updatesFrequently)
                    .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: status)
            }
            HStack(spacing: 12) {
                Button("Type a Name", systemImage: "character.cursor.ibeam") { typing = true }
                if allowed == true {
                    // for cards the live picture can't get: one sharp photo, read as a whole
                    Button("Take Photo", systemImage: "camera") { takePhoto() }
                        .disabled(snapping)
                }
            }
            .buttonStyle(.glass)
            .controlSize(.large)
        }
        .padding(.bottom, 8)
        .padding(.horizontal)
    }

    /// The Camera app's lens buttons: "0.5", "1×", "4". The picked one shows the "×" and the accent colour.
    private var lensPicker: some View {
        let picked = zoom > 0 ? Lens.picked(zoom, in: lenses) : lenses.first { $0.label == "1" } ?? lenses.first
        return HStack(spacing: 2) {
            ForEach(lenses) { lens in
                let on = lens == picked
                Button {
                    zoom = lens.zoom
                } label: {
                    Text(on ? lens.label + "×" : lens.label)
                        .font(.footnote.weight(.semibold).monospacedDigit())
                        .foregroundStyle(on ? Color.accentColor : .white)
                        .frame(width: 36, height: 36)
                        .background(.black.opacity(on ? 0.45 : 0.25), in: .circle)
                        .frame(width: 44, height: 44) // the hit area
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(lens.label) times zoom")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(2)
        .glassEffect(.regular, in: .capsule)
        .sensoryFeedback(.selection, trigger: zoom)
    }

    private var noCamera: some View {
        ContentUnavailableView {
            Label("No Camera", systemImage: "camera")
        } description: {
            Text("Allow the camera for Conclave in Settings to scan cards, or type a card's name instead.")
        } actions: {
            if allowed == false, let settings = URL(string: UIApplication.openSettingsURLString) {
                Link("Open Settings", destination: settings)
            }
        }
    }

    /// Where the scanner reads: the card frame and a little around it, as cards are rarely held exactly in it.
    static func region(around frame: CGRect) -> CGRect {
        frame.insetBy(dx: -frame.width * 0.05, dy: -frame.height * 0.05)
    }

    // MARK: - What the camera read

    private func read(_ items: [(text: String, points: [CGPoint])], frame: CGRect) {
        guard running, !snapping else { return }
        let lines = items.map { ReadLine($0.text, points: $0.points, frame: frame) }
        let card = CardRead(lines)
        seen = ScanSeen(lines: lines.map { $0.rect(in: frame) }, card: card, frame: frame)
        if busy {
            waiting = card
        } else {
            identify(card)
        }
    }

    private func identify(_ card: CardRead) {
        guard let reader else { return }
        busy = true
        if status.isIdle, let name = card.names.first { status = .reading(name) }
        Task {
            let hit = await reader.identify(card)
            busy = false
            guard running else { return }
            take(steadiness.next(card, hit), read: card)
            if let next = waiting {
                waiting = nil
                identify(next)
            }
        }
    }

    private func take(_ outcome: ScanSteadiness.Outcome, read card: CardRead) {
        switch outcome {
        case .found(let printing):
            show(printing)
        case .maybe(let printing):
            status = .maybe(printing.shownName)
        case .alreadyAdded:
            break  // keeps "… added, show the next card"
        case .nothing:
            if card.isEmpty {
                status = .looking
            } else if let name = card.names.first, status.isIdle || status.isReading {
                status = .reading(name)
            }
        }
    }
}

extension CardScanView {
    /// The add sheet for a found card.
    private func show(_ printing: Printing) {
        status = .found(printing.shownName)
        hits += 1
        AccessibilityNotification.Announcement("Found \(printing.shownName)").post()
        // added or not, the same card waits until the frame was empty, else "Cancel" would reopen it at once
        steadiness.added(printing)
        added = false
        found = printing
    }

    /// "Take Photo": the scanner's camera takes one full photo, Vision reads all of it, and the reader tries
    /// card frames of a few sizes around the one on the screen (`PhotoRead`, like `scanPhoto()` in `scan.js`).
    private func takePhoto() {
        guard let reader, !snapping else { return }
        snapping = true
        status = .photo
        let layout = layout
        Task {
            defer { snapping = false }
            guard let image = try? await shutter.photo() else {
                status = .noCard
                return
            }
            let lines = await PhotoText.read(image)
            var hits: [ReadHit] = []
            for frame in PhotoRead.frames(around: layout.frame) {
                let placed = lines.map { line in
                    let box = PhotoRead.screenRect(of: line.box, photo: image.size, screen: layout.screen)
                    let corners = [CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.maxX, y: box.minY),
                                   CGPoint(x: box.maxX, y: box.maxY), CGPoint(x: box.minX, y: box.maxY)]
                    return ReadLine(line.text, points: corners, frame: frame)
                }
                guard let hit = await reader.identify(CardRead(placed)) else { continue }
                hits.append(hit)
                if hit.bySet && !hit.read.isEmpty { break } // set line and name agree: nothing better to find
            }
            guard running else { return }
            if let hit = PhotoRead.best(hits) {
                show(hit.printing)
            } else {
                status = .noCard
            }
        }
    }
}

/// The screen's size and the card frame on it.
struct ScanLayout: Equatable {
    var screen = CGSize.zero
    var frame = CGRect.zero
}

/// Takes a photo with the scanner's own camera (no second camera session).
@MainActor
final class Shutter {
    weak var scanner: DataScannerViewController?

    struct NoCamera: Error {}

    func photo() async throws -> UIImage {
        guard let scanner, scanner.isScanning else { throw NoCamera() }
        return try await scanner.capturePhoto()
    }
}

/// Vision's text recognition on a still photo: each line's text and its box in the photo (points from the top
/// left, as `UIImage.size` counts them).
enum PhotoText {
    static func read(_ image: UIImage) async -> [(text: String, box: CGRect)] {
        guard let cgImage = image.cgImage else { return [] }
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false // card names aren't dictionary words
        request.recognitionLanguages = ["en-US", "de-DE", "fr-FR", "it-IT", "es-ES", "pt-BR"].map { Locale.Language(identifier: $0) }
        guard let observations = try? await request.perform(on: cgImage, orientation: CGImagePropertyOrientation(image.imageOrientation))
        else { return [] }
        return observations.compactMap { observation in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            return (text, observation.boundingBox.toImageCoordinates(image.size, origin: .upperLeft))
        }
    }
}

extension CGImagePropertyOrientation {
    /// The same turn as a `UIImage`'s, so Vision reads the photo upright.
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}

/// What the overlay draws: the boxes of every read line (screen points), and which ones were the name
/// and the set line.
struct ScanSeen: Equatable {
    var lines: [CGRect] = []
    var card = CardRead()
    var frame = CGRect.zero
}

/// The status pill's sentence.
enum ScanStatus: Equatable {
    case looking
    case reading(String)
    case maybe(String)
    case found(String)
    case added(String)
    /// "Take Photo" is reading its photo.
    case photo
    /// The photo showed no card.
    case noCard

    var text: String {
        switch self {
        case .looking: "Hold a card in the frame"
        case .reading(let name): "Reading “\(name)”…"
        case .maybe(let name): "\(name)? Hold still"
        case .found(let name): "Found \(name)"
        case .added(let name): "\(name) added. Show the next card"
        case .photo: "Reading the photo…"
        case .noCard: "No card found. Try again"
        }
    }

    var symbol: String {
        switch self {
        case .looking: "viewfinder"
        case .reading: "text.viewfinder"
        case .maybe: "questionmark.circle"
        case .found: "checkmark.circle.fill"
        case .added: "checkmark.circle"
        case .photo: "camera.viewfinder"
        case .noCard: "exclamationmark.circle"
        }
    }

    var isFound: Bool { if case .found = self { true } else { false } }
    var isReading: Bool { if case .reading = self { true } else { false } }
    /// Nothing better to say yet: a read name may replace it.
    var isIdle: Bool {
        switch self {
        case .looking, .added, .noCard: true
        default: false
        }
    }
}

/// The scanner's overlay: the room outside the card frame dimmed, the frame, a faint box on each line the
/// camera reads, and the name and the set line marked and labelled. With Reduce Motion the boxes fade
/// instead of moving.
private struct ScanOverlay: View {
    let frame: CGRect
    let seen: ScanSeen
    let status: ScanStatus
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var nameRect: CGRect? { seen.card.nameLine.map { $0.rect(in: seen.frame) } }
    private var setRect: CGRect? { seen.card.setLine.map { $0.rect(in: seen.frame) } }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // the room outside the frame, dimmed: a full rectangle with the card cut out
            Path { path in
                path.addRect(CGRect(x: -2000, y: -2000, width: 6000, height: 6000))
                path.addPath(CardShape().path(in: frame))
            }
            .fill(.black.opacity(0.5), style: FillStyle(eoFill: true))

            CardShape()
                .stroke(status.isFound ? Color.accentColor : .white.opacity(0.85), lineWidth: status.isFound ? 4 : 2)
                .frame(width: frame.width, height: frame.height)
                .scaleEffect(status.isFound && !reduceMotion ? 1.03 : 1)
                .offset(x: frame.minX, y: frame.minY)
                .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.3, bounce: 0.4), value: status.isFound)

            // where the name and the set line sit on a card, while nothing is read
            if seen.lines.isEmpty {
                hint(CGRect(x: frame.minX + frame.width * 0.06, y: frame.minY + frame.height * 0.035,
                            width: frame.width * 0.7, height: frame.height * 0.07), label: "Name")
                hint(CGRect(x: frame.minX + frame.width * 0.05, y: frame.minY + frame.height * 0.92,
                            width: frame.width * 0.4, height: frame.height * 0.05), label: "Set & Number")
            }

            ForEach(Array(seen.lines.enumerated()), id: \.offset) { _, rect in
                if rect != nameRect, rect != setRect {
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(.white.opacity(0.35), lineWidth: 1)
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                }
            }
            if let nameRect, let name = seen.card.names.first {
                marked(nameRect, label: name)
            }
            if let setRect, let line = seen.card.line {
                marked(setRect, label: line.set.uppercased() + (line.number.isEmpty ? "" : " #\(line.number)") + " · \(line.lang.uppercased())")
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : .easeOut(duration: 0.12), value: seen)
        .allowsHitTesting(false)
        .accessibilityHidden(true) // the status pill says it in words
    }

    /// A line the reader uses: outlined in the accent colour, with what it read above it.
    private func marked(_ rect: CGRect, label: String) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.accentColor.opacity(0.15))
                .stroke(Color.accentColor, lineWidth: 2)
                .frame(width: rect.width + 8, height: rect.height + 6)
                .offset(x: rect.minX - 4, y: rect.minY - 3)
            Text(label)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .foregroundStyle(Color("OnAccent"))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.accentColor, in: .capsule)
                .offset(x: rect.minX - 4, y: rect.minY - 24)
        }
        .transition(.opacity)
    }

    private func hint(_ rect: CGRect, label: String) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 4)
                .stroke(.white.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.7))
                .offset(x: rect.minX, y: rect.maxY + 2)
        }
        .transition(.opacity)
    }
}

/// VisionKit's live scanner for text, reading inside `region`. It reports every line it sees, with the
/// four corners, whenever they change.
struct TextScanner: UIViewControllerRepresentable {
    let region: CGRect
    let running: Bool
    /// The picked lens's zoom factor; nil keeps the scanner's own.
    var zoom: Double?
    var torch = false
    var camera: BackCamera?
    var shutter: Shutter?
    let onLines: @MainActor ([(text: String, points: [CGPoint])]) -> Void

    /// English and German first; the others printed on cards where the phone reads them.
    private static var languages: [String] {
        let supported = DataScannerViewController.supportedTextRecognitionLanguages
        return ["en-US", "de-DE", "fr-FR", "it-IT", "es-ES", "pt-BR"].filter(supported.contains)
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.text(languages: Self.languages)],
            qualityLevel: .accurate,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: true,
            isGuidanceEnabled: false, // the status pill guides
            isHighlightingEnabled: false // the overlay draws its own boxes
        )
        scanner.delegate = context.coordinator
        shutter?.scanner = scanner
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        context.coordinator.onLines = onLines
        if region.width > 0, scanner.regionOfInterest != region { scanner.regionOfInterest = region }
        if running, !scanner.isScanning {
            try? scanner.startScanning()
        } else if !running, scanner.isScanning {
            scanner.stopScanning() // the camera rests while the add sheet is open
        }
        context.coordinator.wanted = zoom
        context.coordinator.applyZoom(scanner)
        if scanner.isScanning { camera?.setTorch(torch) }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onLines: onLines) }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onLines: @MainActor ([(text: String, points: [CGPoint])]) -> Void
        /// The picked lens's zoom, and the one set last: only a new pick sets it, so a pinch isn't undone.
        var wanted: Double?
        private var applied: Double?

        /// Sets the picked zoom once the camera runs and knows its range (that comes a moment after the start,
        /// so every new read tries again until it took).
        func applyZoom(_ scanner: DataScannerViewController) {
            guard let wanted, wanted != applied, scanner.isScanning, scanner.maxZoomFactor > scanner.minZoomFactor else { return }
            applied = wanted
            scanner.zoomFactor = min(max(wanted, scanner.minZoomFactor), scanner.maxZoomFactor)
        }

        init(onLines: @escaping @MainActor ([(text: String, points: [CGPoint])]) -> Void) {
            self.onLines = onLines
        }

        private func report(_ items: [RecognizedItem], from scanner: DataScannerViewController) {
            applyZoom(scanner)
            onLines(items.compactMap { item in
                guard case .text(let text) = item else { return nil }
                let b = text.bounds
                return (text.transcript, [b.topLeft, b.topRight, b.bottomRight, b.bottomLeft])
            })
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            report(allItems, from: dataScanner)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didUpdate updatedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            report(allItems, from: dataScanner)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didRemove removedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            report(allItems, from: dataScanner)
        }
    }
}


/// The back camera the scanner uses, for what VisionKit doesn't offer: its lenses (where it switches from the
/// ultra-wide to the main camera and on to the tele) and its flashlight.
@MainActor
final class BackCamera {
    let device: AVCaptureDevice?

    init() {
        let kinds: [AVCaptureDevice.DeviceType] = [.builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera]
        device = kinds.lazy.compactMap { AVCaptureDevice.default($0, for: .video, position: .back) }.first
    }

    var switchOvers: [Double] { device?.virtualDeviceSwitchOverVideoZoomFactors.map(\.doubleValue) ?? [] }
    var ultraWide: Bool { device?.constituentDevices.contains { $0.deviceType == .builtInUltraWideCamera } ?? false }
    var hasTorch: Bool { device?.hasTorch ?? false }
    /// How far the lens buttons go: the tele's switch-over and a little beyond, never past what the camera can.
    var maxZoom: Double { Double(device?.maxAvailableVideoZoomFactor ?? 10) }

    /// The flashlight goes off by itself when the camera stops (a sheet, "Done"), so it's set again on every start.
    func setTorch(_ on: Bool) {
        guard let device, device.hasTorch, device.torchMode != (on ? .on : .off), (try? device.lockForConfiguration()) != nil else { return }
        device.torchMode = on ? .on : .off
        device.unlockForConfiguration()
    }
}
