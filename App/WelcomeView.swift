import ConclaveCore
import SwiftUI

/// The first screen: what the app is and where pairing will happen. For now it only checks a
/// pairing link or code with `Pairing.parse`, so the core package is wired in from day one;
/// connecting to the server follows in milestone 1.
struct WelcomeView: View {
    @State private var link = ""
    @State private var server = ""

    private var pairing: Pairing? { Pairing.parse(link, server: server) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "rectangle.stack.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.tint)
                        Text("Your decks, opponents and collection, soon right on your iPhone.")
                            .font(.headline)
                    }
                    .padding(.vertical, 4)
                }
                Section {
                    TextField("Link or code", text: $link)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    TextField("Server (only with a code)", text: $server)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Pair")
                } footer: {
                    Text("On your PC: Settings › Sync › Pair a device.")
                }
                if let pairing {
                    Section("Recognized") {
                        LabeledContent("Server", value: pairing.server.host() ?? "")
                        LabeledContent("Code", value: pairing.code)
                    }
                }
            }
            .navigationTitle("Conclave")
        }
    }
}

#Preview {
    WelcomeView()
}
