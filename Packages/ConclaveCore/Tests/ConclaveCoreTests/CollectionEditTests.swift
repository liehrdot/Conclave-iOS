import Foundation
import Testing
@testable import ConclaveCore

@Suite struct CollectionEditTests {
    static let base = APICasesTests.file["bases"]!["default"]!
    static let merge = APICasesTests.file["bases"]!["collection-update-merge"]!
    static let library = try! ReadModel.decode(base)

    static var solRing: CollectionEntry { library.collection.first { $0.id == "c1" }! }
    static var forests: CollectionEntry { library.collection.first { $0.id == "c2" }! }

    /// What the phone shows after it saved `payload`: the outbox's op applied on top of `model`.
    static func after(_ type: String, _ payload: JSONValue?, on model: JSONValue = base) throws -> ReadModel {
        let op = PendingOp(type: type, payload: try #require(payload))
        return try ReadModel.decode(Optimistic.apply([op], to: model))
    }

    @Test func groupsSearchAndFilters() throws {
        let library = try ReadModel.decode(Self.merge)
        let all = library.collectionGroups()
        #expect(all.map(\.name) == ["Forest", "Sol Ring"])
        #expect(all[1].entries.map(\.id) == ["c1", "c4x"] && all[1].copies == 3)
        #expect(library.collectionGroups(matching: " SOL ").map(\.name) == ["Sol Ring"])
        #expect(library.collectionGroups(matching: "c2").map(\.name) == ["Sol Ring"])  // the set code's start
        #expect(library.collectionGroups(matching: "kiste").first?.entries.map(\.id) == ["c4x"])  // the place
        #expect(library.collectionGroups(matching: "meren").map(\.name) == ["Forest"])  // a deck place by its name
        #expect(library.collectionGroups(filter: .proxy).isEmpty)
        #expect(library.collectionGroups(filter: .original).count == 2)
    }

    @Test func totalsCountCopiesAndValueOriginalsOnly() throws {
        let library = try ReadModel.decode(Self.merge)
        let totals = library.collectionTotals
        #expect(totals.cards == 13 && totals.proxies == 0 && totals.originals == 13)
        #expect(totals.value == Decimal(string: "3.6"))  // 3 Sol Rings at 1.20; the Forests have no price
        var proxied = library
        proxied.collection[1].proxy = true
        #expect(proxied.collectionTotals.value == Decimal(string: "1.2") && proxied.collectionTotals.proxies == 2)
    }

    @Test func placesNameTheDeckOrTheText() throws {
        #expect(Self.library.placeName(of: Self.forests) == Self.library.decks.first { $0.slug == "meren" }?.name)
        #expect(Self.library.placeName(of: Self.solRing) == "Binder")
        var library = try ReadModel.decode(Self.merge)
        library.collection.append(CollectionEntry(id: "x", name: "Island", qty: 5, place: "binder "))
        #expect(library.knownPlaces.map(\.place) == ["Binder", "Kiste"])  // most cards first, each once
        #expect(library.knownPlaces.map(\.cards) == [7, 1])
    }

    @Test func quantityChangesWithItsOldValue() throws {
        #expect(CollectionEdit.quantity(Self.solRing, to: 2) == nil)
        let payload = CollectionEdit.quantity(Self.solRing, to: 4)
        #expect(payload?["prev"] == .object(["qty": .int(2)]))
        #expect(try Self.after("collection.update", payload).collection.first { $0.id == "c1" }?.qty == 4)
        #expect(CollectionEdit.quantity(Self.solRing, to: 20_000)?["qty"] == .int(9999))
    }

    @Test func removingKeepsWhatUndoNeeds() throws {
        let payload = CollectionEdit.remove(Self.solRing)
        let removed = try Self.after("collection.update", payload)
        #expect(!removed.collection.contains { $0.id == "c1" })
        // undo = `collection.add` of the restore, which brings the same entry back
        let (type, back) = try #require(Outbox.inverse("collection.update", payload))
        let restored = try ReadModel.decode(Optimistic.apply([PendingOp(type: type, payload: back)], to: Optimistic.apply(
            [PendingOp(type: "collection.update", payload: payload)], to: Self.base)))
        #expect(restored.collection == Self.library.collection)
    }

    @Test func flagsAndTheirUndo() throws {
        #expect(CollectionEdit.proxy(Self.solRing, false) == nil)
        let proxy = CollectionEdit.proxy(Self.solRing, true)
        #expect(try Self.after("collection.update", proxy).collection.first { $0.id == "c1" }?.proxy == true)
        #expect(Outbox.inverse("collection.update", try #require(proxy))?.1["proxy"] == .bool(false))
        let foil = CollectionEdit.foil(Self.forests, true)
        #expect(try Self.after("collection.update", foil).collection.first { $0.id == "c2" }?.foil == true)
    }

    @Test func movingToADeckOrAPlace() throws {
        let decks = Self.library.decks
        #expect(CollectionEdit.move(Self.solRing, place: "  Binder ") == nil)  // where it is already
        #expect(CollectionEdit.move(Self.forests, deck: "meren") == nil)
        let box = CollectionEdit.move(Self.forests, place: "Kiste   3")
        #expect(box?["place"] == .string("Kiste 3") && box?["place_deck"] == .string(""))
        #expect(box?["prev"] == .object(["place": .string(""), "place_deck": .string("meren")]))
        // a typed deck name means that deck
        let name = try #require(decks.first { $0.slug == "meren" }?.name)
        let typed = CollectionEdit.move(Self.solRing, place: name.uppercased(), decks: decks)
        #expect(typed?["place_deck"] == .string("meren") && typed?["place"] == .string(""))
        let none = CollectionEdit.move(Self.solRing)
        #expect(try Self.after("collection.update", none).collection.first { $0.id == "c1" }?.place == "")
    }

    @Test func movingWhereAnEqualEntryIsMergesThem() throws {
        let library = try ReadModel.decode(Self.merge)
        let kiste = try #require(library.collection.first { $0.id == "c4x" })
        let after = try Self.after("collection.update", CollectionEdit.move(kiste, place: "binder"), on: Self.merge)
        #expect(after.collection.filter { $0.name == "Sol Ring" }.map(\.qty) == [3])
    }

    @Test func addsAndTheirUndo() throws {
        let entry: JSONValue = .object(["name": .string("Sol Ring"), "qty": .int(2), "place": .string("Binder"),
                                        "scryfall_id": .string("4cbc6901-6a4a-4d0a-83ea-7eefa3b35021")])
        let added = PendingOp(type: "collection.add", payload: .object(["entry": entry]))
        let more = try ReadModel.decode(Optimistic.apply([added], to: Self.base))
        #expect(more.collection.first { $0.id == "c1" }?.qty == 4)
        let (type, back) = try #require(Outbox.inverse(added.type, added.payload))
        let undone = try ReadModel.decode(Optimistic.apply([added, PendingOp(type: type, payload: back)], to: Self.base))
        #expect(undone.collection == Self.library.collection)
        // a card without a Scryfall id keeps its picture
        let typed = PendingOp(type: "collection.add", payload: .object(["entry": .object([
            "name": .string("Plains"), "qty": .int(1), "image": .string("https://cards.scryfall.io/normal/x.jpg")])]))
        let plains = try ReadModel.decode(Optimistic.apply([typed], to: Self.base)).collection.first { $0.name == "Plains" }
        #expect(plains?.image?.absoluteString == "https://cards.scryfall.io/normal/x.jpg" && plains?.id == typed.id)
    }

    @Test func refusedChangesShowNothing() throws {
        let unknown = PendingOp(type: "collection.update", payload: .object(["id": .string("nope"), "qty": .int(3)]))
        let tooMany = PendingOp(type: "collection.add", payload: .object(["entry": .object(["name": .string("Sol Ring"), "qty": .int(100)])]))
        let noName = PendingOp(type: "collection.add", payload: .object(["entry": .object(["name": .string(" "), "qty": .int(1)])]))
        #expect(try ReadModel.decode(Optimistic.apply([unknown, tooMany, noName], to: Self.base)).collection == Self.library.collection)
    }

    @Test func summaries() {
        func summary(_ type: String, _ payload: JSONValue?) -> String {
            PendingOp(type: type, payload: payload ?? .null).summary(in: Self.library)
        }
        #expect(summary("collection.update", CollectionEdit.remove(Self.solRing)) == "Removed Sol Ring")
        #expect(summary("collection.update", CollectionEdit.quantity(Self.solRing, to: 3)) == "Sol Ring: 3 copies")
        #expect(summary("collection.update", CollectionEdit.proxy(Self.solRing, true)) == "Sol Ring as a proxy")
        #expect(summary("collection.update", CollectionEdit.foil(Self.solRing, true)) == "Sol Ring as foil")
        #expect(summary("collection.update", CollectionEdit.move(Self.solRing, place: "Kiste")) == "Sol Ring in Kiste")
        #expect(summary("collection.update", CollectionEdit.move(Self.solRing)) == "Sol Ring without a place")
        #expect(summary("collection.add", .object(["entry": .object(["name": .string("Sol Ring"), "qty": .int(2)])])) == "2 × Sol Ring")
    }
}
