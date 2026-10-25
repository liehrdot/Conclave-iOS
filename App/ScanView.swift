import AVFoundation
import ConclaveCore
import SwiftUI
import VisionKit

/// Pairing by scanning the QR code the PC shows. Apple's own scanner (VisionKit) finds the code;
/// the link in it carries the server's address and the code.
struct ScanView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    /// nil until the camera question is answered.
    @State private var allowed: Bool?
    @State private var busy = false
    @State private var problem: String?

    var body: some View {
        NavigationStack {
            Group {
                if allowed == false || !DataScannerViewController.isSupported {
                    ContentUnavailableView {
                        Label("No Camera", systemImage: "camera")
                    } description: {
                        Text("Allow the camera for Conclave in Settings, or enter the code instead.")
                    }
                } else if allowed == true {
                    QRScanner { found($0) }
                        .ignoresSafeArea()
                }
            }
            .overlay(alignment: .bottom) {
                if busy || problem != nil {
                    Group {
                        if busy {
                            Label("Connecting…", systemImage: "antenna.radiowaves.left.and.right")
                        } else if let problem {
                            Label(problem, systemImage: "exclamationmark.triangle.fill")
                        }
                    }
                    .font(.callout)
                    .padding()
                    .glassEffect(in: .rect(cornerRadius: 20))
                    .padding()
                }
            }
            .navigationTitle("Scan QR Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
            }
            .task {
                allowed = await AVCaptureDevice.requestAccess(for: .video)
            }
            .sensoryFeedback(.error, trigger: problem) { _, new in new != nil }
        }
    }

    private func found(_ text: String) {
        guard !busy else { return }
        guard Pairing.parse(text) != nil else {
            problem = "This QR code isn't a Conclave pairing code."
            return
        }
        busy = true
        problem = nil
        Task {
            defer { busy = false }
            do {
                try await model.pair(text)
                dismiss()
            } catch {
                problem = Connection.message(for: error)
            }
        }
    }
}

/// VisionKit's live scanner, only for QR codes. It reports each newly seen code once.
struct QRScanner: UIViewControllerRepresentable {
    let onCode: @MainActor (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        if !scanner.isScanning { try? scanner.startScanning() }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: @MainActor (String) -> Void

        init(onCode: @escaping @MainActor (String) -> Void) {
            self.onCode = onCode
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in addedItems {
                if case .barcode(let code) = item, let text = code.payloadStringValue {
                    onCode(text)
                    return
                }
            }
        }
    }
}
