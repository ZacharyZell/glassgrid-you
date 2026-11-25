import Foundation

/// Thread-safe recursive JSON value AST for MCP schemas, tool arguments, and structured IPC responses.
public enum JSONValue: Equatable, Hashable, Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    public var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    public var intValue: Int? {
        switch self {
        case .int(let value):
            return value
        case .double(let value) where value.isFinite && value.rounded() == value && value >= Double(Int.min) && value <= Double(Int.max):
            return Int(value)
        default:
            return nil
        }
    }

    public var doubleValue: Double? {
        switch self {
        case .double(let value) where value.isFinite:
            return value
        case .int(let value):
            return Double(value)
        default:
            return nil
        }
    }

    public var arrayValue: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    public var objectValue: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    public var isNull: Bool {
        if case .null = self { return true }
        return false
    }

    public init?(any raw: Any) {
        if raw is NSNull {
            self = .null
            return
        }
        if let string = raw as? String {
            self = .string(string)
            return
        }
        if let number = raw as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                self = .bool(number.boolValue)
            } else {
                let d = number.doubleValue
                if d.isFinite, d.rounded() == d, d >= Double(Int.min), d <= Double(Int.max) {
                    let objCType = String(cString: number.objCType)
                    if objCType == "d" || objCType == "f" {
                        self = .double(d)
                    } else {
                        self = .int(number.intValue)
                    }
                } else if d.isFinite {
                    self = .double(d)
                } else {
                    self = .null
                }
            }
            return
        }
        if let array = raw as? [Any] {
            var converted: [JSONValue] = []
            converted.reserveCapacity(array.count)
            for item in array {
                guard let parsed = JSONValue(any: item) else { return nil }
                converted.append(parsed)
            }
            self = .array(converted)
            return
        }
        if let dict = raw as? [String: Any] {
            var converted: [String: JSONValue] = [:]
            converted.reserveCapacity(dict.count)
            for (key, value) in dict {
                guard let parsed = JSONValue(any: value) else { return nil }
                converted[key] = parsed
            }
            self = .object(converted)
            return
        }
        return nil
    }

    public var toFoundationObject: Any {
        switch self {
        case .null:
            return NSNull()
        case .bool(let value):
            return value
        case .int(let value):
            return value
        case .double(let value):
            return value.isFinite ? value : 0
        case .string(let value):
            return value
        case .array(let items):
            return items.map(\.toFoundationObject)
        case .object(let map):
            var dict: [String: Any] = [:]
            dict.reserveCapacity(map.count)
            for (key, value) in map {
                dict[key] = value.toFoundationObject
            }
            return dict
        }
    }

    public static func decode(from data: Data) throws -> JSONValue {
        let obj = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        guard let parsed = JSONValue(any: obj) else {
            throw NSError(domain: "JSONValue", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unsupported JSON value"])
        }
        return parsed
    }

    public func encodedData(prettyPrinted: Bool = false) throws -> Data {
        var options: JSONSerialization.WritingOptions = [.sortedKeys, .withoutEscapingSlashes]
        if prettyPrinted {
            options.insert(.prettyPrinted)
        }
        switch self {
        case .array, .object:
            return try JSONSerialization.data(withJSONObject: toFoundationObject, options: options)
        default:
            options.insert(.fragmentsAllowed)
            return try JSONSerialization.data(withJSONObject: toFoundationObject, options: options)
        }
    }

    public func encodedString(prettyPrinted: Bool = false) -> String {
        guard let data = try? encodedData(prettyPrinted: prettyPrinted),
              let str = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return str
    }
}

extension JSONValue: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let int = try? container.decode(Int.self) {
            self = .int(int)
        } else if let double = try? container.decode(Double.self) {
            self = double.isFinite ? .double(double) : .null
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([JSONValue].self) {
            self = .array(array)
        } else if let object = try? container.decode([String: JSONValue].self) {
            self = .object(object)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSONValue")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value.isFinite ? value : 0)
        case .string(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        }
    }
}
