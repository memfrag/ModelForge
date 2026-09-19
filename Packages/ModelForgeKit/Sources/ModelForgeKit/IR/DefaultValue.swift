import Foundation

/// A validated default.
///
/// Numeric values keep their **lexeme** rather than a parsed `Double`, so the spelling the
/// author wrote is exactly what lands in the generated code. That is what keeps output
/// byte-identical across runs.
public enum DefaultValue: Sendable, Hashable {
    case string(String)
    case boolean(Bool)
    case integer(lexeme: String)
    case float(lexeme: String)
    case null
    case emptyList
    case emptySet
    case emptyMap
    case enumCase(String)

    public var described: String {
        switch self {
        case .string(let value): "\"\(value)\""
        case .boolean(let value): value ? "true" : "false"
        case .integer(let lexeme), .float(let lexeme): lexeme
        case .null: "null"
        case .emptyList: "[]"
        case .emptySet: "[]"
        case .emptyMap: "{}"
        case .enumCase(let name): ".\(name)"
        }
    }
}

/// `@deprecated` with an optional explanation.
public struct Deprecation: Sendable, Hashable {
    public let message: String?

    public init(message: String?) {
        self.message = message
    }
}
