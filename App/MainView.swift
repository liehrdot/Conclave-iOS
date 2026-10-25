import ConclaveCore
import SwiftUI

/// A paired phone: the tabs. Decks and Opponents for now; the table and the cards follow.
struct MainView: View {
    let device: Device
    @State private var page: Page = AppModel.startScreen?.hasPrefix("opponent") == true ? .opponents : .decks

    enum Page: Hashable { case decks, opponents }

    var body: some View {
        TabView(selection: $page) {
            Tab("Decks", systemImage: "rectangle.stack", value: Page.decks) {
                DecksView(device: device)
            }
            Tab("Opponents", systemImage: "person.2", value: Page.opponents) {
                OpponentsView(device: device)
            }
        }
        .tabViewStyle(.sidebarAdaptable) // a sidebar on the iPad, a tab bar on the iPhone
    }
}

/// What a list shows before the first download, or when there is nothing yet.
struct LibraryPlaceholder: View {
    let empty: (title: String, systemImage: String, text: String)
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.library == nil {
            if let problem = model.problem {
                ContentUnavailableView {
                    Label("Can't Load", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(problem)
                } actions: {
                    Button("Try Again") { Task { await model.refresh() } }
                }
            } else {
                ProgressView("Loading…")
            }
        } else {
            ContentUnavailableView(empty.title, systemImage: empty.systemImage, description: Text(empty.text))
        }
    }
}

/// The toolbar button to the settings, on every tab's first screen.
struct SettingsButton: View {
    let device: Device
    @State private var open = AppModel.startScreen == "settings"

    var body: some View {
        Button("Settings", systemImage: "gearshape") { open = true }
            .sheet(isPresented: $open) { SettingsView(device: device) }
    }
}

/// "Demo" in the top bar while the made-up account is open, so it is never taken for real data.
/// A tap opens the settings, where "Leave Demo" is.
struct DemoBadge: View {
    let device: Device
    @State private var open = false

    var body: some View {
        Button("Demo") { open = true }
            .font(.subheadline.weight(.semibold))
            .accessibilityHint("This is a made-up account. Opens the settings.")
            .sheet(isPresented: $open) { SettingsView(device: device) }
    }
}

/// Where the phone is connected, and signing out; in the demo, what it is and "Leave Demo".
struct SettingsView: View {
    let device: Device
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var confirming = false

    var body: some View {
        NavigationStack {
            Form {
                if model.inDemo {
                    Section {
                        Label("This is a made-up account to look around in. Nothing here is sent anywhere.", systemImage: "theatermasks")
                        Button("Leave Demo") {
                            Task {
                                await model.leaveDemo()
                                dismiss()
                            }
                        }
                    } header: {
                        Text("Demo")
                    } footer: {
                        Text("Then pair the app with Conclave on your PC to see your own decks.")
                    }
                } else {
                    Section("Connection") {
                        LabeledContent("Server", value: device.server.host() ?? device.server.absoluteString)
                        LabeledContent("This device", value: device.name)
                        if let problem = model.problem {
                            Label(problem, systemImage: "wifi.exclamationmark")
                                .foregroundStyle(.secondary)
                        }
                    }
                    Section {
                        Button("Sign Out", role: .destructive) { confirming = true }
                    } footer: {
                        Text("Your decks stay on your PC.")
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("Sign out this \(device.name)?", isPresented: $confirming, titleVisibility: .visible) {
                Button("Sign Out", role: .destructive) {
                    Task {
                        await model.signOff()
                        dismiss()
                    }
                }
            } message: {
                Text("It is removed from your sync server. Your decks stay on your PC.")
            }
        }
    }
}

/// A deck's or opponent's colour identity as small mana-coloured dots, like the cards' pips.
struct ColorPips: View {
    let colors: String

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(letters.enumerated()), id: \.offset) { _, letter in
                Circle()
                    .fill(Self.fill(letter))
                    .overlay(Circle().strokeBorder(.primary.opacity(0.25), lineWidth: 0.5))
                    .frame(width: 12, height: 12)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(letters.map(Self.name).formatted(.list(type: .and)))
    }

    private var letters: [Character] { colors.isEmpty ? ["C"] : Array(colors.uppercased()) }

    static func fill(_ letter: Character) -> Color {
        switch letter {
        case "W": Color(red: 0.97, green: 0.94, blue: 0.82)
        case "U": Color(red: 0.25, green: 0.53, blue: 0.85)
        case "B": Color(red: 0.25, green: 0.22, blue: 0.22)
        case "R": Color(red: 0.86, green: 0.30, blue: 0.22)
        case "G": Color(red: 0.20, green: 0.58, blue: 0.33)
        default: Color(red: 0.75, green: 0.73, blue: 0.70)
        }
    }

    static func name(_ letter: Character) -> String {
        switch letter {
        case "W": "white"
        case "U": "blue"
        case "B": "black"
        case "R": "red"
        case "G": "green"
        default: "colorless"
        }
    }
}

/// "3–2" or "3–2–1" with draws; the person's own wins first.
func recordText(wins: Int, losses: Int, draws: Int) -> String {
    draws > 0 ? "\(wins)–\(losses)–\(draws)" : "\(wins)–\(losses)"
}
