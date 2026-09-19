import Foundation

/// Highlights the generated Swift and Kotlin previews.
///
/// Generated code is a narrow, fully known subset of each language — no string
/// interpolation, no operators, no closures — so a small lexical pass gives results
/// indistinguishable from a real parser's, for both languages, in one place.
///
/// It also takes the set of type names the project declares, so a model's own types colour
/// as types rather than falling back to a capitalisation heuristic.
public enum GeneratedCodeLexer {

    public static func spans(in text: String,
                             language: Language,
                             knownTypeNames: Set<String> = []) -> [HighlightSpan] {
        let profile = LanguageProfile.profile(for: language)
        let units = Array(text.utf16)
        var spans: [HighlightSpan] = []
        var index = 0

        while index < units.count {
            let unit = units[index]

            // Whitespace
            if unit == 0x20 || unit == 0x09 || unit == 0x0A || unit == 0x0D {
                index += 1
                continue
            }

            // Line comments, including `///` documentation
            if unit == 0x2F, index + 1 < units.count, units[index + 1] == 0x2F {
                let start = index
                let isDoc = index + 2 < units.count && units[index + 2] == 0x2F
                while index < units.count, units[index] != 0x0A { index += 1 }
                spans.append(.init(kind: isDoc ? .docComment : .comment, range: start..<index))
                continue
            }

            // Block comments, including Kotlin's `/** … */`
            if unit == 0x2F, index + 1 < units.count, units[index + 1] == 0x2A {
                let start = index
                let isDoc = profile.usesBlockDocComments
                    && index + 2 < units.count && units[index + 2] == 0x2A
                index += 2
                while index + 1 < units.count, !(units[index] == 0x2A && units[index + 1] == 0x2F) {
                    index += 1
                }
                index = min(index + 2, units.count)
                spans.append(.init(kind: isDoc ? .docComment : .comment, range: start..<index))
                continue
            }

            // Strings
            if unit == 0x22 {
                let start = index
                index += 1
                while index < units.count, units[index] != 0x22, units[index] != 0x0A {
                    if units[index] == 0x5C { index += 1 }
                    index += 1
                }
                index = min(index + 1, units.count)
                spans.append(.init(kind: .string, range: start..<index))
                continue
            }

            // Annotations: @Serializable, @file:OptIn, @available
            if profile.hasAnnotations, unit == 0x40 {
                let start = index
                index += 1
                while index < units.count, isIdentifier(units[index]) || units[index] == 0x3A {
                    index += 1
                }
                spans.append(.init(kind: .attribute, range: start..<index))
                continue
            }

            // Numbers
            if isDigit(unit) {
                let start = index
                while index < units.count,
                      isDigit(units[index]) || units[index] == 0x2E || units[index] == 0x5F
                        || units[index] == 0x66 || units[index] == 0x4C {   // f, L suffixes
                    index += 1
                }
                spans.append(.init(kind: .number, range: start..<index))
                continue
            }

            // Identifiers, including backtick-escaped ones
            if isIdentifierStart(unit) || unit == 0x60 {
                let start = index
                if units[index] == 0x60 {
                    index += 1
                    while index < units.count, units[index] != 0x60 { index += 1 }
                    index = min(index + 1, units.count)
                } else {
                    while index < units.count, isIdentifier(units[index]) { index += 1 }
                }
                let word = String(decoding: Array(units[start..<index]), as: UTF16.self)
                spans.append(.init(kind: kind(of: word, profile: profile, known: knownTypeNames),
                                   range: start..<index))
                continue
            }

            // Everything else is punctuation.
            let start = index
            index += 1
            spans.append(.init(kind: .punctuation, range: start..<index))
        }

        return spans
    }

    private static func kind(of word: String,
                             profile: LanguageProfile,
                             known: Set<String>) -> HighlightKind {
        if profile.keywords.contains(word) { return .keyword }
        let bare = word.trimmingCharacters(in: CharacterSet(charactersIn: "`"))
        if known.contains(bare) { return .typeName }
        // Generated code follows the usual convention, so a leading capital means a type.
        if let first = bare.first, first.isUppercase {
            // A SCREAMING_SNAKE word is an enum constant, not a type.
            return bare.allSatisfy { $0.isUppercase || $0.isNumber || $0 == "_" } && bare.count > 1
                ? .enumCase
                : .typeName
        }
        return .fieldName
    }

    private static func isDigit(_ unit: UInt16) -> Bool {
        unit >= 0x30 && unit <= 0x39
    }

    private static func isIdentifierStart(_ unit: UInt16) -> Bool {
        (unit >= 0x41 && unit <= 0x5A) || (unit >= 0x61 && unit <= 0x7A) || unit == 0x5F || unit >= 0x80
    }

    private static func isIdentifier(_ unit: UInt16) -> Bool {
        isIdentifierStart(unit) || isDigit(unit)
    }
}
