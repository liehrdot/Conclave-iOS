import ConclaveCore
import SwiftUI

/// The first screen of an unpaired phone: what the app is, and the two ways to pair it.
/// Scanning comes first because the PC shows a QR code; typing the code is the fallback.
struct WelcomeView: View {
    @State private var scanning: Bool
    @State private var entering: Bool
    /// Why the phone isn't paired any more (signed off on the PC).
    let notice: String?

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
                    .font(.system(size: 56))
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
                        .foregroundStyle(.black) // black on the neon, like the PWA: white on it is unreadable
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color("Neon"))
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
