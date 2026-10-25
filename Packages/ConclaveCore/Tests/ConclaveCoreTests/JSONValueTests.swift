import Foundation
import Testing
@testable import ConclaveCore

@Suite struct JSONValueTests {
    private func decode(_ text: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
    }

    @Test func keepsEveryKind() throws {
        let value = try decode(#"{"a": null, "b": true, "c": 1, "d": 1.5, "e": "x", "f": [1, "y"]}"#)
        #expect(value["a"] == .null)
        #expect(value["b"] == .bool(true))
        #expect(value["c"] == .int(1))
        #expect(value["d"] == .double(1.5))
        #expect(value["e"]?.string == "x")
        #expect(value["f"]?[1] == .string("y"))
        #expect(value["c"]?.int == 1)
        #expect(value["b"]?.bool == true)
        #expect(value["e"]?.int == nil)
        #expect(value["f"]?.array?.count == 2)
        #expect(value.object?.count == 6)
    }

    @Test func numbersAndFlagsStayApart() throws {
        #expect(try decode("1") == .int(1))
        #expect(try decode("0") == .int(0))
        #expect(try decode("false") == .bool(false))
    }

    @Test func missingKeysAndIndexesAreNil() throws {
        let value = try decode(#"{"list": [1]}"#)
        #expect(value["nope"] == nil)
        #expect(value["list"]?[3] == nil)
        #expect(value[0] == nil)
        #expect(JSONValue.string("x")["key"] == nil)
    }

    @Test func roundTrips() throws {
        let value = try decode(#"{"deck": {"cards": [{"name": "Sol Ring", "qty": 1}], "proxy": false, "price": 1.5, "last": null}}"#)
        let again = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value))
        #expect(again == value)
    }
}
