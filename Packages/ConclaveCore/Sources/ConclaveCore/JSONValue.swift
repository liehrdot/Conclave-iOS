/// Any JSON value, kept as it came.
///
/// The read model and the operations' payloads are plain JSON with many optional keys, and the PC
/// adds new ones over time. Typed models come for the parts a screen shows; this keeps the rest
/// intact, so the app can apply an operation to its copy of the read model the way the server does
/// (`appops.apply`) and compare it with the server's answer without losing keys it doesn't know.
public enum JSONValue: Hashable, Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    /// `value["decks"]`; nil when this is not an object or has no such key.
    public subscript(key: String) -> JSONValue? {
        if case .object(let object) = self { object[key] } else { nil }
    }

    /// `value[0]`; nil when this is not an array or the index is out of range.
    public subscript(index: Int) -> JSONValue? {
        if case .array(let array) = self, array.indices.contains(index) { array[index] } else { nil }
    }

    public var string: String? { if case .string(let text) = self { text } else { nil } }
    public var int: Int? { if case .int(let number) = self { number } else { nil } }
    public var bool: Bool? { if case .bool(let flag) = self { flag } else { nil } }
    public var array: [JSONValue]? { if case .array(let array) = self { array } else { nil } }
    public var object: [String: JSONValue]? { if case .object(let object) = self { object } else { nil } }
}

extension JSONValue: Codable {
    public init(from decoder: any Decoder) throws {
        let value = try decoder.singleValueContainer()
        // Bool before the numbers and Int before Double, so 1 stays an Int and true stays a Bool.
        if value.decodeNil() { self = .null }
        else if let flag = try? value.decode(Bool.self) { self = .bool(flag) }
        else if let number = try? value.decode(Int.self) { self = .int(number) }
        else if let number = try? value.decode(Double.self) { self = .double(number) }
        else if let text = try? value.decode(String.self) { self = .string(text) }
        else if let array = try? value.decode([JSONValue].self) { self = .array(array) }
        else { self = .object(try value.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: any Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .null: try value.encodeNil()
        case .bool(let flag): try value.encode(flag)
        case .int(let number): try value.encode(number)
        case .double(let number): try value.encode(number)
        case .string(let text): try value.encode(text)
        case .array(let array): try value.encode(array)
        case .object(let object): try value.encode(object)
        }
    }
}
