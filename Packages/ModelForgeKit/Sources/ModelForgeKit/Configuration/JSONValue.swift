import Foundation

/// A minimal JSON tree.
///
/// Config.json is decoded twice: once into the typed configuration the app and emitters
/// use, and once into one of these. On save, the typed values are merged *over* the
/// original tree, so a key written by a newer version of ModelForge survives a round trip
/// through an older one instead of being silently dropped.
public indirect enum JSONValue: Sendable, Hashable, Codable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container,
                                                   debugDescription: "Unrecognised JSON value")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    public var object: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    /// `other` wins wherever the two overlap; keys only `self` has are kept.
    ///
    /// Objects merge recursively. Arrays and scalars are replaced wholesale, because
    /// merging them element-wise would be guesswork.
    public func deepMerging(_ other: JSONValue) -> JSONValue {
        guard case .object(let mine) = self, case .object(let theirs) = other else {
            return other
        }
        var merged = mine
        for (key, value) in theirs {
            if let existing = merged[key] {
                merged[key] = existing.deepMerging(value)
            } else {
                merged[key] = value
            }
        }
        return .object(merged)
    }
}
