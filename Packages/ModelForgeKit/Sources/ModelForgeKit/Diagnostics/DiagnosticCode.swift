import Foundation

/// A stable identifier for each kind of problem the compiler reports.
///
/// Tests assert on codes rather than on message text, so wording can be improved without
/// rewriting fixtures.
public enum DiagnosticCode: String, Sendable, Hashable, CaseIterable {

    // Lexical
    case invalidCharacter
    case unterminatedString
    case invalidEscape

    // Syntactic
    case expectedDeclaration
    case expectedName
    case expectedLeftBrace
    case expectedRightBrace
    case expectedColon
    case expectedType
    case expectedLiteral
    case expectedPayload
    case unexpectedToken

    // Semantic: names and types
    case unknownType
    case duplicateDeclaration
    case duplicateField
    case duplicateEnumCase
    case duplicateUnionCase
    case builtinRedeclared
    case reservedName
    case genericArity

    /// `Int` has a different width on each platform and is rejected outright.
    case ambiguousIntWidth

    // Semantic: values and attributes
    case invalidDefaultValue
    case unknownEnumCase
    case unknownAttribute
    case invalidAttributeArguments
    case attributeNotAllowedHere
    case redundantAttribute
    case transientRequiresDefault
    case duplicateSerializedName

    // Semantic: unions
    case invalidUnionPayload
    case discriminatorClash

    // Semantic: structure
    case recursiveModel

    public var severityHint: Diagnostic.Severity {
        switch self {
        case .reservedName, .redundantAttribute:
            .warning
        default:
            .error
        }
    }
}
