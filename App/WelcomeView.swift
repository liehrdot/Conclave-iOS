import ConclaveCore
import SwiftUI

/// The first screen of an unpaired phone: what the app is, and the two ways to pair it.
/// Scanning comes first because the PC shows a QR code; typing the code is the fallback; the demo
/// shows the app with a made-up account to anyone without a PC at hand.
struct WelcomeView: View {
    @Environment(AppModel.self) private var model
    @State private var scanning: Bool
    @State private var entering: Bool
    /// Why the phone isn't paired any more (signed off on the PC).
    let notice: String?
    /// The big symbol grows with the text size, like the title under it.
    @ScaledMetric(relativeTo: .largeTitle) private var iconSize: CGFloat = 56

    init(entering: Bool = false, scanning: Bool = false, notice: String? = nil) {
        self.notice = notice
        _entering = State(initialValue: entering)
        _scanning = State(initialValue: scanning)
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 16) {
                Image(systemName: "rectangle.stack.fill")
                    .font(.system(size: iconSize))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text("Conclave")
                    .font(.largeTitle.bold())
                Text("Your decks, opponents and games from your PC, with you at the table.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if let notice {
                    Label(notice, systemImage: "person.crop.circle.badge.xmark")
                        .font(.callout)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(.fill.tertiary, in: .rect(cornerRadius: 16))
                }
            }
            Spacer()
            VStack(spacing: 12) {
                Button {
                    scanning = true
                } label: {
                    Label("Scan QR Code", systemImage: "qrcode.viewfinder")
                        .font(.headline)
                        .foregroundStyle(Color("OnAccent")) // white on the dark green, black on the neon
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button("Enter Code") {
                    entering = true
                }
                .font(.headline)
                .controlSize(.large)

                Text("On your PC: Settings › Sync › Pair a device.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button("No PC at hand? Try the Demo") {
                    model.startDemo()
                }
                .font(.subheadline)
                .padding(.top, 8)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
        .frame(maxWidth: 480)
        .sheet(isPresented: $entering) {
            EnterCodeView()
        }
        .fullScreenCover(isPresented: $scanning) {
            ScanView()
        }
    }
}

#Preview {
    WelcomeView()
        .environment(AppModel(store: MemoryDeviceStore(), cache: nil, transport: URLSession.conclave()))
}
