import Foundation

/// A name the project declares, or a built-in.
public struct Symbol: Sendable, Hashable {

    public enum Kind: Sendable, Hashable {
        case model
        case `enum`
        case union
        case alias
        case scalar(ScalarType)
        /// `Set` and `Map`, which are spelled like identifiers but are not declarable.
        case container

        var namedKind: NamedKind? {
            switch self {
            case .model: .model
            case .enum: .enum
            case .union: .union
            case .alias: .alias
            case .scalar, .container: nil
            }
        }

        var isBuiltin: Bool {
            switch self {
            case .scalar, .container: true
            default: false
            }
        }
    }

    public let name: String
    public let kind: Kind
    /// Where the type was declared. `nil` for built-ins.
    public let declaredAt: SourceRange?

    public init(name: String, kind: Kind, declaredAt: SourceRange?) {
        self.name = name
        self.kind = kind
        self.declaredAt = declaredAt
    }
}

/// Every name visible in a project.
///
/// There is exactly one of these per project, not one per file: a ModelForge bundle is a
/// single flat namespace, so a type declared in any `.model` file is visible from all of
/// them. That is what removed `import` from the language.
public struct SymbolTable: Sendable {

    private var symbols: [String: Symbol] = [:]

    public init() {
        for scalar in ScalarType.allCases {
            symbols[scalar.rawValue] = Symbol(name: scalar.rawValue,
                                              kind: .scalar(scalar),
                                              declaredAt: nil)
        }
        for container in ["Set", "Map"] {
            symbols[container] = Symbol(name: container, kind: .container, declaredAt: nil)
        }
    }

    public subscript(name: String) -> Symbol? {
        symbols[name]
    }

    /// Declare a type. Returns the existing symbol when the name is already taken, so the
    /// caller can point the diagnostic at the first declaration.
    public mutating func declare(_ symbol: Symbol) -> Symbol? {
        if let existing = symbols[symbol.name] {
            return existing
        }
        symbols[symbol.name] = symbol
        return nil
    }

    /// Names worth offering as a correction for a misspelling. Excludes `Set` and `Map`,
    /// which are never written bare.
    public var suggestableNames: [String] {
        symbols.values
            .filter { if case .container = $0.kind { return false } else { return true } }
            .map(\.name)
            .sorted()
    }
}
