import Foundation
import Testing
@testable import ConclaveCore

/// The shared operation cases from Conclave (`docs/app-api/ops.json`, copied by
/// `scripts/update_api_cases.sh`): what the server's `appops.apply` does with each operation.
/// For now these tests only check that the file is complete and readable; milestone 2's optimistic
/// apply will run every case against it.
@Suite struct APICasesTests {
    static let file: JSONValue = {
        let url = Bundle.module.url(forResource: "ops", withExtension: "json")!
        return try! JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
    }()

    static var cases: [JSONValue] { file["cases"]?.array ?? [] }

    @Test func isTheVersionWeRead() {
        #expect(Self.file["version"] == .int(1))
        #expect(Self.cases.count > 20)
    }

    @Test func everyCaseHasABaseAnOpAndAnOutcome() throws {
        let bases = try #require(Self.file["bases"]?.object)
        for item in Self.cases {
            let name = item["name"]?.string ?? "?"
            let base = try #require(item["base"]?.string, "\(name): no base")
            #expect(bases[base] != nil, "\(name): unknown base \(base)")
            #expect(item["op"]?["type"]?.string != nil, "\(name): no op type")
            // exactly one: what the server changed, or the German message it refused with
            #expect((item["after"] == nil) != (item["error"] == nil), "\(name): needs after or error")
        }
    }

    @Test func coversEveryOperationThePhoneSends() {
        let types = Set(Self.cases.compactMap { $0["op"]?["type"]?.string })
        let phone: Set = [
            "game.add", "game.delete", "opponent.add", "opponent.update", "opponent.note",
            "opponent.note_delete", "opponent.delete", "deck.new", "deck.edit", "deck.flags",
            "deck.pin_order", "collection.add", "collection.update",
        ]
        #expect(phone.isSubset(of: types), "missing: \(phone.subtracting(types).sorted())")
    }

    @Test func basesAreReadModels() throws {
        let bases = try #require(Self.file["bases"]?.object)
        for (name, base) in bases {
            for key in ["decks", "opponents", "games", "collection"] {
                #expect(base[key]?.array != nil, "base \(name) has no \(key) list")
            }
        }
    }
}
