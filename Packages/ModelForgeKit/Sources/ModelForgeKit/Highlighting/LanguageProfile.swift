import Foundation

/// What `GeneratedCodeLexer` needs to know about a target language.
public struct LanguageProfile: Sendable {

    public let keywords: Set<String>
    /// Whether `@Name` marks an annotation, as it does in both Swift and Kotlin.
    public let hasAnnotations: Bool
    /// Whether `/** … */` is the documentation form (Kotlin) rather than `///` (Swift).
    public let usesBlockDocComments: Bool

    public static let swift = LanguageProfile(
        keywords: [
            "struct", "enum", "class", "actor", "protocol", "extension", "typealias",
            "let", "var", "func", "init", "self", "Self", "try", "throws", "return",
            "switch", "case", "default", "if", "else", "guard", "for", "in", "while",
            "import", "public", "internal", "private", "fileprivate", "open", "static",
            "indirect", "nil", "true", "false", "any", "some", "where", "as", "is"
        ],
        hasAnnotations: true,
        usesBlockDocComments: false
    )

    public static let kotlin = LanguageProfile(
        keywords: [
            "package", "import", "class", "interface", "object", "data", "sealed", "enum",
            "val", "var", "fun", "typealias", "return", "when", "if", "else", "for",
            "while", "is", "as", "in", "null", "true", "false", "this", "super",
            "public", "private", "internal", "protected", "override", "companion", "const"
        ],
        hasAnnotations: true,
        usesBlockDocComments: true
    )

    public static func profile(for language: Language) -> LanguageProfile {
        switch language {
        case .swift: .swift
        case .kotlin: .kotlin
        }
    }
}
