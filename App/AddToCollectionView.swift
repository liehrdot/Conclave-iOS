import ConclaveCore
import SwiftUI

/// "Add to Collection": which printing, original or proxy, foil, language, place and how many, then one
/// `collection.add` with "Undo" in the toast. Original/Proxy and the place are remembered for the next card.
/// Mirrors `addSheet()` in the PWA's `scan.js`; the scanner opens it too, later.
struct AddToCollectionView: View {
    /// The card's English name.
    let name: String
    /// A German name was what matched: start from the German printing.
    var german = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            AddToCollectionForm(name: name, german: german) { dismiss() }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                }
        }
    }
}

/// The add sheet's content, also pushed from `AddByNameView`; `done` closes the whole sheet after "Add".
struct AddToCollectionForm: View {
    let name: String
    var german = false
    let done: () -> Void
    @Environment(AppModel.self) private var model
    @AppStorage("addProxy") private var lastProxy = false
    @AppStorage("addPlace") private var lastPlace = ""
    @AppStorage("addDeck") private var lastDeck = ""
    @State private var draft: CollectionAddDraft?
    @State private var problem: String?

    var body: some View {
        Group {
            if draft != nil {
                form
            } else if let problem {
                ContentUnavailableView {
                    Label("Can't Load the Card", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(problem)
                } actions: {
                    Button("Try Again") { Task { await load() } }
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Add to Collection")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Add") { add() }
                    .disabled(draft == nil)
            }
        }
        .task { if draft == nil { await load() } }
    }

    private var draftBinding: Binding<CollectionAddDraft> {
        Binding(get: { draft! }, set: { draft = $0 })
    }

    @ViewBuilder private var form: some View {
        let draft = draftBinding
        let printing = draft.wrappedValue.printing
        List {
            Section {
                header(printing, proxy: draft.wrappedValue.proxy, foil: draft.wrappedValue.foil)
                NavigationLink("Other Printing") {
                    PrintingPicker(printing: printing, lang: draft.wrappedValue.lang) { draftBinding.wrappedValue.pick($0) }
                }
                if let owned {
                    Label(owned, systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                }
            }
            .materialRow()
            Section {
                Picker("Kind", selection: draft.proxy) {
                    Text("Original").tag(false)
                    Text("Proxy").tag(true)
                }
                .pickerStyle(.segmented)
                Toggle("Foil", isOn: Binding(get: { draft.wrappedValue.foil }, set: { draftBinding.wrappedValue.setFoil($0) }))
                    .disabled(!(printing.hasFoil && printing.hasNonfoil)) // this printing comes only one way
                Picker("Language", selection: Binding(get: { draft.wrappedValue.lang }, set: { language($0) })) {
                    ForEach(languages, id: \.self) { Text(Self.languageName($0)).tag($0) }
                }
                NavigationLink {
                    PlacePicker(art: name, place: draft.wrappedValue.place, deck: draft.wrappedValue.deck) { place, deck in
                        let picked = CollectionEdit.placed(place: place, deck: deck, decks: model.library?.decks ?? [])
                        draftBinding.wrappedValue.place = picked.place
                        draftBinding.wrappedValue.deck = picked.deck
                    }
                } label: {
                    LabeledContent("Place", value: placeName ?? "None")
                }
                Stepper(value: draft.copies, in: 1...99) {
                    LabeledContent("Copies", value: draft.wrappedValue.copies.formatted())
                }
            }
            .materialRow()
        }
        .artList(over: name)
    }

    /// The printing's picture and facts: its name as printed, the set, number and language, the price.
    private func header(_ printing: Printing, proxy: Bool, foil: Bool) -> some View {
        HStack(alignment: .top, spacing: 14) {
            CardImage(url: printing.image)
                .frame(width: 96)
                .clipShape(.rect(cornerRadius: 5))
            VStack(alignment: .leading, spacing: 3) {
                Text(printing.shownName).font(.headline)
                if printing.shownName != printing.name {
                    Text(printing.name).font(.subheadline).foregroundStyle(.secondary)
                }
                Text(printing.setName).font(.subheadline)
                Text("\(printing.set.uppercased()) · #\(printing.collectorNumber) · \(printing.lang.uppercased())")
                    .font(.subheadline.monospaced())
                    .foregroundStyle(.secondary)
                if !proxy, let price = printing.price(foil: foil).flatMap({ Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX")) }) {
                    Text("About \(price.formatted(.currency(code: "EUR")))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// "Already in your collection: 3 (1 proxy)", or nil.
    private var owned: String? {
        let entries = model.library?.collection.filter { $0.name == name } ?? []
        let copies = entries.reduce(0) { $0 + $1.qty }
        guard copies > 0 else { return nil }
        let proxies = entries.filter(\.proxy).reduce(0) { $0 + $1.qty }
        return "Already in your collection: \(copies)" + (proxies > 0 ? " (\(proxies) proxy)" : "")
    }

    private var placeName: String? {
        guard let draft else { return nil }
        if !draft.deck.isEmpty { return model.library?.decks.first { $0.slug == draft.deck }?.name ?? draft.deck }
        return draft.place.isEmpty ? nil : draft.place
    }

    /// English, German, and the printing's own language when it's another.
    private var languages: [String] {
        var out: [String] = []
        for lang in ["en", "de", draft?.printing.lang, draft?.lang].compactMap({ $0 }) where !out.contains(lang) { out.append(lang) }
        return out
    }

    static func languageName(_ code: String) -> String {
        Locale.current.localizedString(forLanguageCode: code) ?? code.uppercased()
    }

    /// The copy is in another language: the same printing in that language, when Scryfall has it.
    private func language(_ lang: String) {
        guard let printing = draft?.printing else { return }
        draft?.lang = lang
        guard printing.lang != lang else { return }
        Task {
            guard let other = try? await model.cards.scryfall.printing(set: printing.set, number: printing.collectorNumber, lang: lang),
                  draft?.lang == lang else { return }
            draft?.pick(other)
        }
    }

    private func load() async {
        problem = nil
        do {
            let scryfall = model.cards.scryfall
            guard var printing = try await scryfall.printing(named: name) else {
                problem = "Scryfall doesn't know this card."
                return
            }
            if german, let de = try? await scryfall.printing(set: printing.set, number: printing.collectorNumber, lang: "de") {
                printing = de
            }
            var made = CollectionAddDraft(printing, proxy: lastProxy)
            // the place used last, while it still exists
            if !lastDeck.isEmpty, model.library?.decks.contains(where: { $0.slug == lastDeck }) == true {
                made.deck = lastDeck
            } else {
                made.place = lastPlace
            }
            draft = made
        } catch {
            problem = "Adding a card needs a connection to Scryfall."
        }
    }

    private func add() {
        guard let draft else { return }
        lastProxy = draft.proxy
        lastPlace = draft.place
        lastDeck = draft.deck
        Task { await model.save("collection.add", draft.payload()) }
        done()
    }
}

/// "Other Printing": every paper printing of the card, newest first, in English, or in the copy's language
/// and English. A tap picks one. Mirrors `printPage()` in `scan.js`.
private struct PrintingPicker: View {
    let printing: Printing
    let lang: String
    let onPick: (Printing) -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var all: [Printing]?
    @State private var failed = false

    private var shown: [Printing] {
        (all ?? []).filter { lang == "en" ? $0.lang == "en" : $0.lang == lang || $0.lang == "en" }
    }

    var body: some View {
        List {
            ForEach(shown) { other in
                Button {
                    onPick(other)
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        CardImage(url: other.image)
                            .frame(width: 36, height: 50)
                            .clipShape(.rect(cornerRadius: 3))
                        VStack(alignment: .leading, spacing: 2) {
                            // the system's label colours: a button in a list would tint all of its text green
                            Text(other.setName).foregroundStyle(Color.primary)
                            Text("\(other.set.uppercased()) · #\(other.collectorNumber) · \(other.lang.uppercased()) · \(String(other.released.prefix(4)))")
                                .font(.subheadline.monospaced())
                                .foregroundStyle(Color.secondary)
                        }
                        Spacer()
                        if other.id == printing.id {
                            Image(systemName: "checkmark")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .contentShape(.rect)
                }
                .accessibilityAddTraits(other.id == printing.id ? .isSelected : [])
                .materialRow()
            }
        }
        .artList(over: printing.name)
        .overlay {
            if all == nil, !failed {
                ProgressView()
            } else if failed {
                ContentUnavailableView("Can't Load Printings", systemImage: "wifi.exclamationmark",
                                       description: Text("Showing them needs a connection to Scryfall."))
            } else if shown.isEmpty {
                ContentUnavailableView("No Other Printings", systemImage: "rectangle.stack")
            }
        }
        .navigationTitle("Printing")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do {
                all = try await model.cards.scryfall.printings(of: printing.oracleID, anyLanguage: lang != "en")
            } catch {
                failed = true
            }
        }
    }
}

/// "Add a Card" from the Collection tab: a name, English or German, then the add sheet.
/// Mirrors `searchSheet()` in the PWA's `scan.js`.
struct AddByNameView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var hits: [NameHit] = []
    @State private var failed = false

    private var typed: String { query.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        NavigationStack {
            List(hits) { hit in
                NavigationLink {
                    AddToCollectionForm(name: hit.name, german: hit.german != nil) { dismiss() }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(hit.german ?? hit.name)
                        Text(hit.german != nil ? hit.name : hit.type)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .overlay {
                if failed {
                    ContentUnavailableView("Can't Search", systemImage: "wifi.exclamationmark",
                                           description: Text("Finding a card needs a connection to Scryfall."))
                } else if typed.count < 2 {
                    ContentUnavailableView("Add a Card", systemImage: "plus.rectangle.on.rectangle",
                                           description: Text("Type its name, in English or German. Part of it is enough."))
                } else if hits.isEmpty {
                    ContentUnavailableView.search(text: typed)
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Card name")
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .navigationTitle("Add a Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .task(id: typed) {
                guard typed.count >= 2 else { hits = []; return }
                try? await Task.sleep(for: .milliseconds(300)) // wait for the typing to pause
                guard !Task.isCancelled else { return }
                do {
                    hits = try await model.cards.scryfall.find(name: typed)
                    failed = false
                } catch {
                    failed = !Task.isCancelled
                }
            }
        }
    }
}
