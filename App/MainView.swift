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

/// The settings, like the iPhone's own: a short list, with the details one tap deeper.
/// In the demo: what it is and "Leave Demo". Mirrors the PWA's settings sheet in `forms.js`.
struct SettingsView: View {
    let device: Device
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var confirming = false
    @AppStorage(Look.key) private var savedLook = Look.today.rawValue

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Look", selection: $savedLook) {
                        ForEach(Look.allCases) { look in
                            VStack(alignment: .leading) {
                                Text(look.title)
                                Text(look.blurb).font(.caption).foregroundStyle(.secondary)
                            }
                            .tag(look.rawValue)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Look (Preview)")
                } footer: {
                    Text("Try the looks on the Decks tab. Only in this preview build.")
                }
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
                    Section {
                        NavigationLink {
                            ConnectionView(device: device)
                        } label: {
                            ConnectionRow(device: device)
                        }
                        Link(destination: device.server.appending(path: "app/")) {
                            Label("Open the Web App", systemImage: "safari")
                        }
                    } footer: {
                        Text("The web app has what this app can't do yet, like logging games and the collection.")
                    }
                }
                Section {
                    NavigationLink {
                        AboutView()
                    } label: {
                        LabeledContent {
                            Text(AboutView.version)
                        } label: {
                            Label("About Conclave", systemImage: "info.circle")
                        }
                    }
                }
                if !model.inDemo {
                    Section {
                        Button("Sign Out", role: .destructive) { confirming = true }
                    }
                }
            }
            .task { await model.loadStatus() }
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

/// The connection in one row: the server, and whether all is well ("Up to date · Desk online").
private struct ConnectionRow: View {
    let device: Device
    @Environment(AppModel.self) private var model

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(device.server.host() ?? device.server.absoluteString)
                Text(summary)
                    .font(.footnote)
                    .foregroundStyle(model.problem == nil ? Color.secondary : Color.orange)
            }
        } icon: {
            Image(systemName: model.problem == nil ? "checkmark.icloud" : "exclamationmark.icloud")
        }
    }

    private var summary: String {
        if model.problem != nil { return "Can't update right now" }
        let online = model.status?.pcs.filter(\.online).map(\.name) ?? []
        let state = model.lastUpdate == nil ? "Connected" : "Up to date"
        return online.isEmpty ? state : "\(state) · \(online.formatted(.list(type: .and))) online"
    }
}

/// Where this phone is connected and which PCs share the server.
struct ConnectionView: View {
    let device: Device
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section {
                LabeledContent("Server", value: device.server.host() ?? device.server.absoluteString)
                LabeledContent("This device", value: device.name)
                if let problem = model.problem {
                    Label(problem, systemImage: "wifi.exclamationmark")
                        .foregroundStyle(.secondary)
                } else if let updated = model.lastUpdate {
                    LabeledContent("Last update") {
                        Text(updated, format: .relative(presentation: .named))
                    }
                }
            }
            Section {
                if let status = model.status {
                    if status.pcs.isEmpty {
                        Text("No PC is connected to this server yet.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(status.pcs, id: \.name) { pc in
                        LabeledContent {
                            if pc.online {
                                Label("Online", systemImage: "circle.fill")
                                    .labelStyle(.titleAndIcon)
                                    .foregroundStyle(.green)
                                    .imageScale(.small)
                            } else if let seen = pc.lastSeen(now: status.now, received: model.statusReceived ?? .now) {
                                Text("Seen \(seen, format: .relative(presentation: .named))")
                            } else {
                                Text("Not seen yet")
                            }
                        } label: {
                            Label(pc.name, systemImage: "desktopcomputer")
                        }
                    }
                } else if model.statusFailed {
                    Label("Can't reach the server right now.", systemImage: "wifi.exclamationmark")
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }
            } header: {
                Text("Your PCs")
            } footer: {
                Text("New decks and changes arrive here after a PC syncs.")
            }
        }
        .navigationTitle("Connection")
        .refreshable { await model.loadStatus() }
    }
}

/// Version, where the code and the card data come from, and the licences.
struct AboutView: View {
    var body: some View {
        Form {
            Section {
                LabeledContent("Version", value: Self.version)
                Link(destination: URL(string: "https://github.com/liehrdot/Conclave-iOS")!) {
                    Label("Source Code", systemImage: "chevron.left.forwardslash.chevron.right")
                }
            }
            Section("Thanks to") {
                Link(destination: URL(string: "https://scryfall.com")!) {
                    LabeledContent("Scryfall", value: "Card data and images")
                }
                Link(destination: URL(string: "https://mana.andrewgioia.com")!) {
                    LabeledContent("Mana by Andrew Gioia", value: "Mana symbols (OFL)")
                }
            }
            Section {
            } footer: {
                Text("Fan Content permitted under the Fan Content Policy. Not approved/endorsed by Wizards. Portions of the materials used are property of Wizards of the Coast. © Wizards of the Coast LLC.")
            }
        }
        .navigationTitle("About Conclave")
    }

    /// "0.1.0 (1)": the version and build from the app's Info.plist.
    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
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
