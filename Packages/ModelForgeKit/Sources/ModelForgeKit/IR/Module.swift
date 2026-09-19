import Foundation

/// A field on a model, fully resolved.
public struct FieldDefinition: Sendable, Hashable {
    public let name: String
    public let type: TypeRef
    public let defaultValue: DefaultValue?
    /// The wire name, when `@json` renamed it.
    public let serializedName: String?
    /// `@transient`: present in the generated type, absent from the wire representation.
    public let isTransient: Bool
    public let documentation: [String]
    public let deprecation: Deprecation?
    /// Where the field's name appears, so a diagnostic found later can point at it.
    public let origin: SourceRange?

    public init(name: String, type: TypeRef, defaultValue: DefaultValue?,
                serializedName: String?, isTransient: Bool,
                documentation: [String], deprecation: Deprecation?,
                origin: SourceRange? = nil) {
        self.name = name
        self.type = type
        self.defaultValue = defaultValue
        self.serializedName = serializedName
        self.isTransient = isTransient
        self.documentation = documentation
        self.deprecation = deprecation
        self.origin = origin
    }

    /// The name this field takes on the wire.
    public var wireName: String {
        serializedName ?? name
    }

    /// Whether the field participates in encoding and decoding at all.
    public var isSerialized: Bool {
        !isTransient
    }
}

public struct ModelDefinition: Sendable, Hashable {
    public let name: String
    public let fields: [FieldDefinition]
    public let documentation: [String]
    public let deprecation: Deprecation?
    public let sourceFile: SourceFileID
    public let origin: SourceRange?
    /// Just the declared name, which is what "jump to definition" selects.
    public let nameOrigin: SourceRange?

    public init(name: String, fields: [FieldDefinition], documentation: [String],
                deprecation: Deprecation?, sourceFile: SourceFileID, origin: SourceRange?,
                nameOrigin: SourceRange? = nil) {
        self.name = name
        self.fields = fields
        self.documentation = documentation
        self.deprecation = deprecation
        self.sourceFile = sourceFile
        self.origin = origin
        self.nameOrigin = nameOrigin
    }

    /// Whether any field carries a default.
    ///
    /// This decides whether the Swift emitter writes a custom `init(from:)`: a default
    /// means the key may be absent from the wire representation, which synthesized
    /// `Codable` does not implement.
    public var hasDefaults: Bool {
        fields.contains { $0.defaultValue != nil }
    }

    /// Whether the emitters need an explicit `CodingKeys` enum.
    public var needsCodingKeys: Bool {
        fields.contains { $0.serializedName != nil || $0.isTransient }
    }
}

public struct EnumCaseDefinition: Sendable, Hashable {
    public let name: String
    public let serializedName: String?
    public let documentation: [String]
    public let deprecation: Deprecation?

    public init(name: String, serializedName: String?,
                documentation: [String], deprecation: Deprecation?) {
        self.name = name
        self.serializedName = serializedName
        self.documentation = documentation
        self.deprecation = deprecation
    }

    /// The wire value. Defaults to the DSL spelling, per §12 — the platforms rename the
    /// *constant*, never the value.
    public var wireName: String {
        serializedName ?? name
    }
}

public struct EnumDefinition: Sendable, Hashable {
    public let name: String
    public let cases: [EnumCaseDefinition]
    public let documentation: [String]
    public let deprecation: Deprecation?
    public let sourceFile: SourceFileID
    public let origin: SourceRange?
    /// Just the declared name, which is what "jump to definition" selects.
    public let nameOrigin: SourceRange?

    public init(name: String, cases: [EnumCaseDefinition], documentation: [String],
                deprecation: Deprecation?, sourceFile: SourceFileID, origin: SourceRange?,
                nameOrigin: SourceRange? = nil) {
        self.name = name
        self.cases = cases
        self.documentation = documentation
        self.deprecation = deprecation
        self.sourceFile = sourceFile
        self.origin = origin
        self.nameOrigin = nameOrigin
    }
}

public struct UnionCaseDefinition: Sendable, Hashable {
    public let name: String
    public let payload: TypeRef
    public let serializedName: String?
    public let documentation: [String]
    public let deprecation: Deprecation?
    /// Where the payload type appears, so payload problems point at the payload.
    public let payloadOrigin: SourceRange?

    public init(name: String, payload: TypeRef, serializedName: String?,
                documentation: [String], deprecation: Deprecation?,
                payloadOrigin: SourceRange? = nil) {
        self.name = name
        self.payload = payload
        self.serializedName = serializedName
        self.documentation = documentation
        self.deprecation = deprecation
        self.payloadOrigin = payloadOrigin
    }

    public var wireName: String {
        serializedName ?? name
    }
}

public struct UnionDefinition: Sendable, Hashable {
    public let name: String
    public let cases: [UnionCaseDefinition]
    /// The JSON key holding the case tag. `type` unless `@discriminator` says otherwise.
    public let discriminator: String
    /// Whether a case's payload reaches back to this union, which makes the Swift enum
    /// `indirect`.
    public let isRecursive: Bool
    public let documentation: [String]
    public let deprecation: Deprecation?
    public let sourceFile: SourceFileID
    public let origin: SourceRange?
    /// Just the declared name, which is what "jump to definition" selects.
    public let nameOrigin: SourceRange?

    public init(name: String, cases: [UnionCaseDefinition], discriminator: String,
                isRecursive: Bool, documentation: [String], deprecation: Deprecation?,
                sourceFile: SourceFileID, origin: SourceRange?,
                nameOrigin: SourceRange? = nil) {
        self.name = name
        self.cases = cases
        self.discriminator = discriminator
        self.isRecursive = isRecursive
        self.documentation = documentation
        self.deprecation = deprecation
        self.sourceFile = sourceFile
        self.origin = origin
        self.nameOrigin = nameOrigin
    }

    public static let defaultDiscriminator = "type"
}

public struct AliasDefinition: Sendable, Hashable {
    public let name: String
    public let target: TypeRef
    public let documentation: [String]
    public let deprecation: Deprecation?
    public let sourceFile: SourceFileID
    public let origin: SourceRange?
    /// Just the declared name, which is what "jump to definition" selects.
    public let nameOrigin: SourceRange?

    public init(name: String, target: TypeRef, documentation: [String],
                deprecation: Deprecation?, sourceFile: SourceFileID, origin: SourceRange?,
                nameOrigin: SourceRange? = nil) {
        self.name = name
        self.target = target
        self.documentation = documentation
        self.deprecation = deprecation
        self.sourceFile = sourceFile
        self.origin = origin
        self.nameOrigin = nameOrigin
    }
}

public enum TypeDefinition: Sendable, Hashable {
    case model(ModelDefinition)
    case `enum`(EnumDefinition)
    case union(UnionDefinition)
    case alias(AliasDefinition)

    public var name: String {
        switch self {
        case .model(let definition): definition.name
        case .enum(let definition): definition.name
        case .union(let definition): definition.name
        case .alias(let definition): definition.name
        }
    }

    public var sourceFile: SourceFileID {
        switch self {
        case .model(let definition): definition.sourceFile
        case .enum(let definition): definition.sourceFile
        case .union(let definition): definition.sourceFile
        case .alias(let definition): definition.sourceFile
        }
    }

    /// Where the declaration begins, so the editor can jump to it.
    public var origin: SourceRange? {
        switch self {
        case .model(let definition): definition.origin
        case .enum(let definition): definition.origin
        case .union(let definition): definition.origin
        case .alias(let definition): definition.origin
        }
    }

    /// Just the declared name. Selecting this rather than the whole declaration keeps a
    /// jump from flooding the editor when the type is long.
    public var nameOrigin: SourceRange? {
        switch self {
        case .model(let definition): definition.nameOrigin
        case .enum(let definition): definition.nameOrigin
        case .union(let definition): definition.nameOrigin
        case .alias(let definition): definition.nameOrigin
        }
    }

    public var kind: NamedKind {
        switch self {
        case .model: .model
        case .enum: .enum
        case .union: .union
        case .alias: .alias
        }
    }

    /// Every scalar this definition mentions, for working out Kotlin imports.
    public var referencedScalars: Set<ScalarType> {
        switch self {
        case .model(let definition):
            definition.fields.reduce(into: Set<ScalarType>()) { $0.formUnion($1.type.referencedScalars) }
        case .enum:
            []
        case .union(let definition):
            definition.cases.reduce(into: Set<ScalarType>()) { $0.formUnion($1.payload.referencedScalars) }
        case .alias(let definition):
            definition.target.referencedScalars
        }
    }
}

/// Everything a ModelForge project declares, resolved and ready to emit.
///
/// The whole project is one module with one flat namespace: a bundle's `.model` files see
/// each other without declaring anything, which is why the language has no `import`.
public struct Module: Sendable, Hashable {

    /// Declaration order within each file, files in the order they were given.
    public let types: [TypeDefinition]

    public init(types: [TypeDefinition]) {
        self.types = types
    }

    public func types(in file: SourceFileID) -> [TypeDefinition] {
        types.filter { $0.sourceFile == file }
    }

    public var typeNames: Set<String> {
        Set(types.map(\.name))
    }

    public subscript(name: String) -> TypeDefinition? {
        types.first { $0.name == name }
    }
}
