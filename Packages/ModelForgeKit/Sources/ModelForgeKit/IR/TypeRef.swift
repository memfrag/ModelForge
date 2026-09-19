import Foundation

/// What kind of declaration a named type refers to.
///
/// Resolved during semantic analysis so the emitters never need a symbol table.
public enum NamedKind: String, Sendable, Hashable {
    case model
    case `enum`
    case union
    case alias
}

/// A fully resolved type.
///
/// Syntax quirks are gone by this point: `[T?]` is `.list(.optional(...))` regardless of
/// how it was spelled, and a scalar is distinguishable from a user type without a lookup.
public indirect enum TypeRef: Sendable, Hashable {
    case scalar(ScalarType)
    case named(String, NamedKind)
    case optional(TypeRef)
    case list(TypeRef)
    case set(TypeRef)
    case map(key: TypeRef, value: TypeRef)
    /// A name semantic analysis could not resolve.
    ///
    /// Deliberately *not* an error state that stops generation: the emitters print it
    /// verbatim, so while the user types `Str` → `Stri` → `String` the previews keep
    /// updating and the diagnostic clears on its own. Generate is blocked separately.
    case unresolved(String)

    public var isOptional: Bool {
        if case .optional = self { return true }
        return false
    }

    /// The type with any outer optional removed.
    public var unwrapped: TypeRef {
        if case .optional(let wrapped) = self { return wrapped }
        return self
    }

    public var scalar: ScalarType? {
        if case .scalar(let scalar) = self { return scalar }
        return nil
    }

    /// Names of every declared type mentioned anywhere inside, used for recursion checks
    /// and to decide which imports a generated file needs.
    public var referencedNames: Set<String> {
        switch self {
        case .scalar: []
        case .named(let name, _): [name]
        case .unresolved(let name): [name]
        case .optional(let wrapped), .list(let wrapped), .set(let wrapped):
            wrapped.referencedNames
        case .map(let key, let value):
            key.referencedNames.union(value.referencedNames)
        }
    }

    /// Every scalar mentioned inside, used to work out a Kotlin file's imports.
    public var referencedScalars: Set<ScalarType> {
        switch self {
        case .scalar(let scalar): [scalar]
        case .named, .unresolved: []
        case .optional(let wrapped), .list(let wrapped), .set(let wrapped):
            wrapped.referencedScalars
        case .map(let key, let value):
            key.referencedScalars.union(value.referencedScalars)
        }
    }

    /// Whether this is a scalar the emitters have to convert on the way to the wire.
    var isScalarNeedingWire: Bool {
        guard case .scalar(let scalar) = self else { return false }
        return scalar == .instant || scalar == .duration
    }

    /// The type written back in DSL notation, for diagnostics and IR dumps.
    public var described: String {
        switch self {
        case .scalar(let scalar): scalar.rawValue
        case .named(let name, _): name
        case .unresolved(let name): name
        case .optional(let wrapped): "\(wrapped.described)?"
        case .list(let element): "[\(element.described)]"
        case .set(let element): "Set<\(element.described)>"
        case .map(let key, let value): "Map<\(key.described), \(value.described)>"
        }
    }
}
