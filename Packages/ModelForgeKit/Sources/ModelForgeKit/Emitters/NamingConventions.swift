import Foundation

/// Identifier transformations the emitters need.
///
/// These live here rather than in a dependency because TextToolbox, despite its name, has
/// no case conversion beyond `capitalizingFirstLetter()`.
public enum NamingConventions {

    /// `applePay` → `APPLE_PAY`, `httpGet` → `HTTP_GET`, `userID` → `USER_ID`.
    ///
    /// Acronym-aware: a run of capitals is one word, and the last capital of a run starts
    /// a new word when a lowercase letter follows it. Without that, `httpGet` would come
    /// out as `H_T_T_P_GET`.
    public static func screamingSnakeCase(_ name: String) -> String {
        words(in: name).map { $0.uppercased() }.joined(separator: "_")
    }

    /// `user` → `User`, `user_profile` → `UserProfile`, `user-profile` → `UserProfile`.
    ///
    /// Used to turn a source file's stem into its generated file's name.
    public static func upperCamelCase(_ name: String) -> String {
        let parts = words(in: name)
        guard !parts.isEmpty else { return name }
        return parts.map { part in
            // An all-caps word is an acronym; leave it alone rather than title-casing it.
            part.allSatisfy { $0.isUppercase || $0.isNumber } && part.count > 1
                ? part
                : part.prefix(1).uppercased() + part.dropFirst().lowercased()
        }.joined()
    }

    /// Split an identifier into words across case changes and separators.
    static func words(in name: String) -> [String] {
        var words: [String] = []
        var current = ""

        func flush() {
            if !current.isEmpty {
                words.append(current)
                current = ""
            }
        }

        let characters = Array(name)
        for (index, character) in characters.enumerated() {
            if character == "_" || character == "-" || character == " " {
                flush()
                continue
            }

            if character.isUppercase, !current.isEmpty {
                let previous = characters[index - 1]
                let nextIsLowercase = index + 1 < characters.count && characters[index + 1].isLowercase
                // Start a new word at a lower→upper boundary, or at the final capital of
                // an acronym that is followed by lowercase ("HTTPGet" → "HTTP", "Get").
                if !previous.isUppercase || nextIsLowercase {
                    flush()
                }
            }


            current.append(character)
        }
        flush()
        return words
    }

    /// Wrap a name in backticks when it collides with a keyword on `language`.
    public static func escaped(_ name: String, keywords: Set<String>) -> String {
        keywords.contains(name) ? "`\(name)`" : name
    }

    public static func escapedForSwift(_ name: String) -> String {
        escaped(name, keywords: ReservedNames.swiftKeywords)
    }

    public static func escapedForKotlin(_ name: String) -> String {
        escaped(name, keywords: ReservedNames.kotlinKeywords)
    }
}
