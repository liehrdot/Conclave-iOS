import ConclaveCore
import SwiftUI

/// "Describe": a card you can't name ("draws a card when one of my creatures dies"). The sync server
/// turns the description into a Scryfall search (Flo's one AI exception; the key is the owner's and
/// stays on the server), the phone runs it, most played first. Nothing found → the server's broader
/// search. Mirrors `bindDescribe()` in the PWA's `screens.js`.
struct DescribeSearch: View {
    @Environment(AppModel.self) private var model
    @State private var text = AppModel.startScreen == "describe" ? "Draws a card whenever one of my creatures dies" : ""
    @State private var colors: [String] = AppModel.startScreen == "describe" ? ["B", "G"] : []
    @State private var types: [String] = []
    @State private var answer: DescribeAnswer?
    /// The search that ran: the answer's query, or its broader one when that found nothing.
    @State private var query = ""
    @State private var broadened = false
    @State private var cards: [Card] = []
    @State private var total = 0
    @State private var next: Int?
    @State private var busy = false
    @State private var problem: String?
    @State private var needsSetup = false
    @State private var settingUp = false
    @State private var shown: DeckView.ShownCard?
    @FocusState private var focused: Bool

    static let colorChoices = zip(DescribeFilter.colors, ["White", "Blue", "Black", "Red", "Green", "Colorless"])
        .map { Options.Choice(key: $0, label: $1) }
    static let typeChoices = DescribeFilter.types.map { Options.Choice(key: $0, label: $0.capitalized) }

    private var ready: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !busy }

    var body: some View {
        List {
            Section {
                TextField("What should the card do?", text: $text, axis: .vertical)
                    .lineLimit(2...6)
                    .focused($focused)
                    .submitLabel(.search)
                    .onSubmit { Task { await find() } }
                    .glassRow()
                ChoiceChips(title: "Colors (optional)", choices: Self.colorChoices, picked: colors) { toggle($0, in: &colors) }
                    .glassRow()
                ChoiceChips(title: "Card type (optional)", choices: Self.typeChoices, picked: types) { toggle($0, in: &types) }
                    .glassRow()
            } footer: {
                if model.inDemo {
                    Text("Describing needs your own sync server, so it doesn't work in the demo.")
                }
            }

            Section {
                // the one green button on the screen
                Button {
                    Task { await find() }
                } label: {
                    Group {
                        if busy { ProgressView().tint(.black) } else { Label("Find Cards", systemImage: "sparkle.magnifyingglass") }
                    }
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity, minHeight: 34)
                }
                .buttonStyle(.glassProminent)
                .tint(Color("Neon"))
                .disabled(!ready || model.inDemo)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            if let problem {
                Section {
                    Label(problem, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .glassRow()
                    if needsSetup {
                        Button("Set Up Search by Description") { settingUp = true }
                            .glassRow()
                    }
                }
            }

            if answer != nil {
                Section {
                    // the search itself, so it can be checked or copied to scryfall.com
                    Text(query)
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                        .glassRow()
                    ForEach(cards, id: \.name) { card in
                        SearchRow(name: card.name, type: card.faces.map(\.typeLine).joined(separator: " // ")) {
                            shown = DeckView.ShownCard(name: card.name)
                        }
                    }
                    if let next {
                        Button("Show More") { Task { await load(page: next) } }
                            .disabled(busy)
                            .glassRow()
                    }
                } header: {
                    GlassHeader(cards.isEmpty ? "No Cards Found" : total == 1 ? "1 Card" : "\(total) Cards")
                } footer: {
                    if broadened { Text("Nothing matched exactly, so this is a broader search.") }
                }
            }
        }
        .glassList(over: cards.first?.name ?? "")
        .scrollDismissesKeyboard(.interactively)
        .sheet(item: $shown) { shown in CardSheet(name: shown.name, copies: []) }
        .sheet(isPresented: $settingUp) {
            NavigationStack { AISetupView() }
        }
    }

    private func toggle(_ key: String, in list: inout [String]) {
        if let index = list.firstIndex(of: key) { list.remove(at: index) } else { list.append(key) }
    }

    /// Asks the server for the search, then runs it on Scryfall; nothing found → the broader one.
    private func find() async {
        guard ready, let server = model.server else { return }
        focused = false
        busy = true
        defer { busy = false }
        problem = nil
        needsSetup = false
        do {
            let got = try await server.describe(text.trimmingCharacters(in: .whitespacesAndNewlines), colors: colors, types: types)
            answer = got
            query = got.query
            broadened = false
            cards = []
            try await run(page: 1)
            if cards.isEmpty, !got.broader.isEmpty {
                query = got.broader
                broadened = true
                try await run(page: 1)
            }
        } catch let error as ServerError {
            needsSetup = error.needsSetup
            problem = needsSetup ? "Search by description isn't set up on your sync server yet." : error.message
        } catch CardError.badQuery {
            problem = "Scryfall couldn't read the search. Try describing it another way."
        } catch {
            problem = "Scryfall didn't answer. Try again in a moment."
        }
    }

    private func load(page: Int) async {
        busy = true
        defer { busy = false }
        do { try await run(page: page) } catch { problem = "Scryfall didn't answer. Try again in a moment." }
    }

    private func run(page: Int) async throws {
        let found = try await model.cards.scryfall.search(query, page: page)
        await model.cards.remember(found.cards)
        cards = page == 1 ? found.cards : cards + found.cards
        total = found.total
        next = found.next
    }
}

/// "Search by Description": the Claude API key the sync server uses, and the model. The key goes to
/// the server and never comes back (only its last four characters). Mirrors `aiPage` in the PWA's
/// `forms.js`.
struct AISetupView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var settings: AISettings?
    @State private var key = ""
    @State private var picked = ""
    @State private var busy = false
    @State private var problem: String?

    var body: some View {
        Form {
            if let settings {
                Section {
                    if settings.fromEnv {
                        Text("The key is set on the server itself.")
                    } else {
                        SecureField(settings.configured ? "New key (now \(settings.keyHint))" : "sk-ant-…", text: $key)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                } header: {
                    Text("Claude API Key")
                } footer: {
                    Text("Your sync server keeps the key and uses it only to turn a description into a Scryfall search. Make one at console.anthropic.com.")
                }
                Section {
                    Picker("Model", selection: $picked) {
                        ForEach(settings.models) { Text($0.label).tag($0.id) }
                    }
                } footer: {
                    Text("The smallest model is enough for almost every search and costs a fraction of a cent. Searches asked before cost nothing.")
                }
            } else if let problem {
                Label(problem, systemImage: "wifi.exclamationmark")
            } else {
                ProgressView()
            }
            if settings != nil, let problem {
                Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            }
        }
        .navigationTitle("Search by Description")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", role: .confirm) { Task { await save() } }
                    .disabled(settings == nil || busy || !changed)
            }
        }
        .task { await load() }
    }

    private var changed: Bool {
        !key.trimmingCharacters(in: .whitespaces).isEmpty || (settings.map { picked != $0.model } ?? false)
    }

    private func load() async {
        guard let server = model.server else {
            problem = "Not available in the demo."
            return
        }
        do {
            let got = try await server.aiSettings()
            settings = got
            picked = got.model
        } catch {
            problem = (error as? ServerError)?.message ?? "Couldn't load the setup. Please try again."
        }
    }

    /// Sends only what changed: an empty key field keeps the stored key.
    private func save() async {
        guard let server = model.server, let settings else { return }
        busy = true
        defer { busy = false }
        let newKey = key.trimmingCharacters(in: .whitespaces)
        do {
            self.settings = try await server.setAI(key: newKey.isEmpty ? nil : newKey, model: picked == settings.model ? nil : picked)
            dismiss()
        } catch {
            problem = (error as? ServerError)?.message ?? "Couldn't save. Please try again."
        }
    }
}
