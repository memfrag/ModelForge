import Foundation

/// Names that would collide with something in the generated code.
///
/// Two different severities apply. A *member* name that is a keyword on either platform is
/// only a nuisance — both emitters escape it with backticks — so it is a warning. A *type*
/// name that collides with a type the emitters themselves generate would produce code that
/// does not compile, so it is an error.
public enum ReservedNames {

    /// Swift keywords that cannot appear unescaped as a property or case name.
    static let swiftKeywords: Set<String> = [
        "associatedtype", "class", "deinit", "enum", "extension", "fileprivate", "func",
        "import", "init", "inout", "internal", "let", "open", "operator", "private",
        "precedencegroup", "protocol", "public", "rethrows", "static", "struct", "subscript",
        "typealias", "var", "break", "case", "catch", "continue", "default", "defer", "do",
        "else", "fallthrough", "for", "guard", "if", "in", "repeat", "return", "throw",
        "switch", "where", "while", "as", "false", "is", "nil", "self", "Self", "super",
        "throws", "true", "try", "Any", "Protocol", "Type"
    ]

    /// Kotlin hard keywords, which likewise need backticks.
    static let kotlinKeywords: Set<String> = [
        "as", "break", "class", "continue", "do", "else", "false", "for", "fun", "if", "in",
        "interface", "is", "null", "object", "package", "return", "super", "this", "throw",
        "true", "try", "typealias", "typeof", "val", "var", "when", "while", "by", "catch",
        "constructor", "delegate", "dynamic", "field", "file", "finally", "get", "import",
        "init", "param", "property", "receiver", "set", "setparam", "value", "where"
    ]

    /// Type names the generated code already uses for something else.
    static let forbiddenTypeNames: Set<String> = [
        // Swift and Kotlin standard-library names the emitters reference directly.
        "String", "Bool", "Int", "Int32", "Int64", "Long", "Float", "Double", "Decimal",
        "BigDecimal", "UUID", "Uuid", "URL", "Date", "LocalDate", "Instant", "Duration",
        "List", "Set", "Map", "Array", "Dictionary", "Optional", "Any", "AnyObject",
        "Codable", "Encodable", "Decodable", "Equatable", "Hashable", "Sendable",
        "Serializable", "CodingKeys", "Self", "Type"
    ]

    /// Whether a member name needs escaping on either platform.
    public static func isKeyword(_ name: String) -> Bool {
        swiftKeywords.contains(name) || kotlinKeywords.contains(name)
    }

    public static func platformsReserving(_ name: String) -> [String] {
        var platforms: [String] = []
        if swiftKeywords.contains(name) { platforms.append("Swift") }
        if kotlinKeywords.contains(name) { platforms.append("Kotlin") }
        return platforms
    }

    /// Whether a declared type may not take this name.
    public static func isForbiddenTypeName(_ name: String) -> Bool {
        forbiddenTypeNames.contains(name)
    }
}
