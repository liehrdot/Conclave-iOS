import ConclaveCore
import SwiftUI

/// What a paired phone shows until the decks arrive (the next milestone 1 PR): where it is
/// connected, and signing out.
struct PairedView: View {
    let device: Device
    @Environment(AppModel.self) private var model
    @State private var confirming = false

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("Connected", systemImage: "checkmark.circle.fill")
            } description: {
                Text("Paired with \(device.server.host() ?? "your server") as “\(device.name)”. Your decks and opponents come here next.")
            }
            .navigationTitle("Conclave")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Sign Out", role: .destructive) { confirming = true }
                }
            }
            .confirmationDialog("Sign out this \(device.name)?", isPresented: $confirming, titleVisibility: .visible) {
                Button("Sign Out", role: .destructive) {
                    Task { await model.signOff() }
                }
            } message: {
                Text("It is removed from your sync server. Your decks stay on your PC.")
            }
        }
    }
}
