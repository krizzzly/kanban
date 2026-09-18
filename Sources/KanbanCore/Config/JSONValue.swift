import Foundation

/// A generic JSON tree for round-trip-safe edits of `~/.hermes/config.json`: every key is kept,
/// including ones this app doesn't know about. Ints and doubles stay distinct so `1` never
/// turns into `1.0` on save.
public enum JSONValue: Sendable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])
}

extension JSONValue: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let b = try? container.decode(Bool.self) { self = .bool(b) }
        else if let i = try? container.decode(Int.self) { self = .int(i) }
        else if let d = try? container.decode(Double.self) { self = .double(d) }
        else if let s = try? container.decode(String.self) { self = .string(s) }
        else if let a = try? container.decode([JSONValue].self) { self = .array(a) }
        else if let o = try? container.decode([String: JSONValue].self) { self = .object(o) }
        else {
            throw DecodingError.dataCorruptedError(in: container,
                                                   debugDescription: "Unbekannter JSON-Wert")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .int(let i): try container.encode(i)
        case .double(let d): try container.encode(d)
        case .bool(let b): try container.encode(b)
        case .null: try container.encodeNil()
        case .array(let a): try container.encode(a)
        case .object(let o): try container.encode(o)
        }
    }
}

// MARK: - Typed accessors

public extension JSONValue {
    var stringValue: String? { if case .string(let s) = self { return s }; return nil }
    var boolValue: Bool? { if case .bool(let b) = self { return b }; return nil }
    var intValue: Int? { if case .int(let i) = self { return i }; return nil }
    var arrayValue: [JSONValue]? { if case .array(let a) = self { return a }; return nil }
    /// Zahl, egal ob sie als `15`, `15.5` oder `"15"` in der Datei steht. `1` und `1.0` sind so
    /// dasselbe Story-Point-Feld, und eine Zahl in Anführungszeichen — wie sie in gewachsenen
    /// Configs vorkommt — gilt ebenfalls, statt als „nicht gesetzt" durchzugehen.
    var doubleValue: Double? {
        switch self {
        case .double(let d): return d
        case .int(let i): return Double(i)
        case .string(let s): return Double(s.trimmingCharacters(in: .whitespaces))
        default: return nil
        }
    }
    var objectValue: [String: JSONValue]? { if case .object(let o) = self { return o }; return nil }
}

// MARK: - Key-path access

public extension JSONValue {
    /// Value at a dotted key path (`["modules", "jira", "baseUrl"]`); nil if any segment is missing.
    func value(at path: [String]) -> JSONValue? {
        guard let first = path.first else { return self }
        guard case .object(let obj) = self, let child = obj[first] else { return nil }
        return child.value(at: Array(path.dropFirst()))
    }

    /// Sets the value at `path`, creating intermediate objects as needed; non-object intermediates
    /// are replaced. Passing `nil` removes the leaf key (empty parent objects are kept — harmless).
    mutating func set(_ value: JSONValue?, at path: [String]) {
        guard let first = path.first else {
            if let value { self = value }
            return
        }
        var obj = objectValue ?? [:]
        if path.count == 1 {
            obj[first] = value
        } else {
            var child = obj[first] ?? .object([:])
            child.set(value, at: Array(path.dropFirst()))
            obj[first] = child
        }
        self = .object(obj)
    }
}
