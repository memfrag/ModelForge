import Foundation

// The syntax tree is faithful to the *text*: every node carries its source range, doc
// comments and attributes are kept exactly as written and validated later, numeric
// literals keep their spelling, and recovery placeholders are representable.
//
// Everything is a value type with associated values rather than a class hierarchy,
// because two code generators exhaustively switch over these nodes and a class tree
// would turn that into a pile of casts.
//
// Node names carry a `Syntax` suffix so they never collide with the resolved IR types
// (`ModelSyntax` vs `ModelDefinition`).

// MARK: - Leaves

public struct IdentifierSyntax: Sendable, Hashable {
    public let text: String
    public let range: SourceRange

    public init(text: String, range: SourceRange) {
        self.text = text
        self.range = range
    }

    /// Recovery inserts these where a name was expected but absent. Semantic analysis
    /// drops the declaration silently rather than reporting a second problem.
    public var isMissing: Bool { text.isEmpty }
}

public struct DocCommentSyntax: Sendable, Hashable {
    public let text: String
    public let range: SourceRange

    public init(text: String, range: SourceRange) {
        self.text = text
        self.range = range
    }
}

public enum LiteralSyntax: Sendable, Hashable {
    case string(String, SourceRange)
    case integer(lexeme: String, SourceRange)
    case float(lexeme: String, SourceRange)
    case boolean(Bool, SourceRange)
    case null(SourceRange)
    case emptyList(SourceRange)
    case emptyMap(SourceRange)
    case enumCase(IdentifierSyntax, SourceRange)

    public var range: SourceRange {
        switch self {
        case .string(_, let range), .integer(_, let range), .float(_, let range),
             .boolean(_, let range), .null(let range), .emptyList(let range),
             .emptyMap(let range), .enumCase(_, let range):
            range
        }
    }

    /// How the literal reads in a diagnostic such as "cannot use a string as a default".
    public var describedForDiagnostic: String {
        switch self {
        case .string: "a string"
        case .integer: "an integer"
        case .float: "a floating-point number"
        case .boolean: "a boolean"
        case .null: "null"
        case .emptyList: "an empty list"
        case .emptyMap: "an empty map"
        case .enumCase(let name, _): "enum case '.\(name.text)'"
        }
    }
}

// MARK: - Types

public indirect enum TypeSyntax: Sendable, Hashable {
    case named(IdentifierSyntax)
    case list(element: TypeSyntax, range: SourceRange)
    case set(element: TypeSyntax, range: SourceRange)
    case map(key: TypeSyntax, value: TypeSyntax, range: SourceRange)
    case optional(wrapped: TypeSyntax, range: SourceRange)
    /// A type the parser could not read. Semantic analysis skips it without reporting,
    /// because the parser has already said what went wrong.
    case missing(SourceRange)

    public var range: SourceRange {
        switch self {
        case .named(let identifier): identifier.range
        case .list(_, let range), .set(_, let range), .map(_, _, let range),
             .optional(_, let range), .missing(let range):
            range
        }
    }

    public var containsMissing: Bool {
        switch self {
        case .missing: true
        case .named: false
        case .list(let element, _), .set(let element, _), .optional(let element, _):
            element.containsMissing
        case .map(let key, let value, _):
            key.containsMissing || value.containsMissing
        }
    }
}

// MARK: - Attributes

public struct AttributeArgumentSyntax: Sendable, Hashable {
    public let label: IdentifierSyntax?
    public let value: LiteralSyntax
    public let range: SourceRange

    public init(label: IdentifierSyntax?, value: LiteralSyntax, range: SourceRange) {
        self.label = label
        self.value = value
        self.range = range
    }
}

public struct AttributeSyntax: Sendable, Hashable {
    public let name: IdentifierSyntax
    public let arguments: [AttributeArgumentSyntax]
    public let range: SourceRange

    public init(name: IdentifierSyntax, arguments: [AttributeArgumentSyntax], range: SourceRange) {
        self.name = name
        self.arguments = arguments
        self.range = range
    }
}

// MARK: - Declarations

public struct FieldSyntax: Sendable, Hashable {
    public let documentation: [DocCommentSyntax]
    public let attributes: [AttributeSyntax]
    public let name: IdentifierSyntax
    public let type: TypeSyntax
    public let defaultValue: LiteralSyntax?
    public let range: SourceRange

    public init(documentation: [DocCommentSyntax], attributes: [AttributeSyntax],
                name: IdentifierSyntax, type: TypeSyntax,
                defaultValue: LiteralSyntax?, range: SourceRange) {
        self.documentation = documentation
        self.attributes = attributes
        self.name = name
        self.type = type
        self.defaultValue = defaultValue
        self.range = range
    }
}

public struct ModelSyntax: Sendable, Hashable {
    public let documentation: [DocCommentSyntax]
    public let attributes: [AttributeSyntax]
    public let name: IdentifierSyntax
    public let fields: [FieldSyntax]
    public let range: SourceRange

    public init(documentation: [DocCommentSyntax], attributes: [AttributeSyntax],
                name: IdentifierSyntax, fields: [FieldSyntax], range: SourceRange) {
        self.documentation = documentation
        self.attributes = attributes
        self.name = name
        self.fields = fields
        self.range = range
    }
}

public struct EnumCaseSyntax: Sendable, Hashable {
    public let documentation: [DocCommentSyntax]
    public let attributes: [AttributeSyntax]
    public let name: IdentifierSyntax
    public let range: SourceRange

    public init(documentation: [DocCommentSyntax], attributes: [AttributeSyntax],
                name: IdentifierSyntax, range: SourceRange) {
        self.documentation = documentation
        self.attributes = attributes
        self.name = name
        self.range = range
    }
}

public struct EnumSyntax: Sendable, Hashable {
    public let documentation: [DocCommentSyntax]
    public let attributes: [AttributeSyntax]
    public let name: IdentifierSyntax
    public let cases: [EnumCaseSyntax]
    public let range: SourceRange

    public init(documentation: [DocCommentSyntax], attributes: [AttributeSyntax],
                name: IdentifierSyntax, cases: [EnumCaseSyntax], range: SourceRange) {
        self.documentation = documentation
        self.attributes = attributes
        self.name = name
        self.cases = cases
        self.range = range
    }
}

public struct UnionCaseSyntax: Sendable, Hashable {
    public let documentation: [DocCommentSyntax]
    public let attributes: [AttributeSyntax]
    public let name: IdentifierSyntax
    public let payload: TypeSyntax
    public let range: SourceRange

    public init(documentation: [DocCommentSyntax], attributes: [AttributeSyntax],
                name: IdentifierSyntax, payload: TypeSyntax, range: SourceRange) {
        self.documentation = documentation
        self.attributes = attributes
        self.name = name
        self.payload = payload
        self.range = range
    }
}

public struct UnionSyntax: Sendable, Hashable {
    public let documentation: [DocCommentSyntax]
    public let attributes: [AttributeSyntax]
    public let name: IdentifierSyntax
    public let cases: [UnionCaseSyntax]
    public let range: SourceRange

    public init(documentation: [DocCommentSyntax], attributes: [AttributeSyntax],
                name: IdentifierSyntax, cases: [UnionCaseSyntax], range: SourceRange) {
        self.documentation = documentation
        self.attributes = attributes
        self.name = name
        self.cases = cases
        self.range = range
    }
}

public struct TypeAliasSyntax: Sendable, Hashable {
    public let documentation: [DocCommentSyntax]
    public let attributes: [AttributeSyntax]
    public let name: IdentifierSyntax
    public let target: TypeSyntax
    public let range: SourceRange

    public init(documentation: [DocCommentSyntax], attributes: [AttributeSyntax],
                name: IdentifierSyntax, target: TypeSyntax, range: SourceRange) {
        self.documentation = documentation
        self.attributes = attributes
        self.name = name
        self.target = target
        self.range = range
    }
}

public enum DeclarationSyntax: Sendable, Hashable {
    case model(ModelSyntax)
    case `enum`(EnumSyntax)
    case union(UnionSyntax)
    case typeAlias(TypeAliasSyntax)

    public var name: IdentifierSyntax {
        switch self {
        case .model(let declaration): declaration.name
        case .enum(let declaration): declaration.name
        case .union(let declaration): declaration.name
        case .typeAlias(let declaration): declaration.name
        }
    }

    public var range: SourceRange {
        switch self {
        case .model(let declaration): declaration.range
        case .enum(let declaration): declaration.range
        case .union(let declaration): declaration.range
        case .typeAlias(let declaration): declaration.range
        }
    }

    public var attributes: [AttributeSyntax] {
        switch self {
        case .model(let declaration): declaration.attributes
        case .enum(let declaration): declaration.attributes
        case .union(let declaration): declaration.attributes
        case .typeAlias(let declaration): declaration.attributes
        }
    }

    public var documentation: [DocCommentSyntax] {
        switch self {
        case .model(let declaration): declaration.documentation
        case .enum(let declaration): declaration.documentation
        case .union(let declaration): declaration.documentation
        case .typeAlias(let declaration): declaration.documentation
        }
    }

    /// The word used when describing this declaration in a diagnostic.
    public var keyword: String {
        switch self {
        case .model: "model"
        case .enum: "enum"
        case .union: "union"
        case .typeAlias: "typealias"
        }
    }
}

/// One parsed `.model` file.
public struct DocumentSyntax: Sendable, Hashable {
    public let file: SourceFileID
    public let declarations: [DeclarationSyntax]

    public init(file: SourceFileID, declarations: [DeclarationSyntax]) {
        self.file = file
        self.declarations = declarations
    }
}
