import Foundation

extension Parser {

    /// `type = primaryType "?"*`
    mutating func parseType(diagnostics: inout DiagnosticBag) -> TypeSyntax {
        var type = parsePrimaryType(diagnostics: &diagnostics)
        while let question = take(.question) {
            type = .optional(wrapped: type, range: type.range.union(question.range))
        }
        return type
    }

    /// `primaryType = IDENT | "[" type "]" | "Set" "<" type ">" | "Map" "<" type "," type ">"`
    ///
    /// `Set` and `Map` are matched here as ordinary identifiers followed by `<`, which is
    /// why they are not lexer keywords: `set: Bool` remains a perfectly good field.
    private mutating func parsePrimaryType(diagnostics: inout DiagnosticBag) -> TypeSyntax {
        if at(.leftBracket) {
            return parseListType(diagnostics: &diagnostics)
        }

        if let name = token.identifierText, lookahead(1).is(.leftAngle) {
            switch name {
            case "Set": return parseSetType(diagnostics: &diagnostics)
            case "Map": return parseMapType(diagnostics: &diagnostics)
            default: break
            }
        }

        if let name = token.identifierText {
            let identifier = take()
            return .named(IdentifierSyntax(text: name, range: identifier.range))
        }

        diagnostics.error(.expectedType,
                          "expected a type, found \(token.describedForDiagnostic)",
                          at: token.range)
        return .missing(previousTokenEnd)
    }

    private mutating func parseListType(diagnostics: inout DiagnosticBag) -> TypeSyntax {
        let open = take()
        let element = parseType(diagnostics: &diagnostics)
        let close = expectClosing(.rightBracket, of: "list type", openedAt: open.range,
                                  diagnostics: &diagnostics)
        return .list(element: element, range: open.range.union(close))
    }

    private mutating func parseSetType(diagnostics: inout DiagnosticBag) -> TypeSyntax {
        let name = take()
        take(.leftAngle)
        let element = parseType(diagnostics: &diagnostics)

        // A stray second argument (`Set<A, B>`) is consumed here rather than derailing the
        // member list, and reported as an arity problem.
        while take(.comma) != nil {
            let extra = parseType(diagnostics: &diagnostics)
            diagnostics.error(.genericArity,
                              "'Set' takes one type argument",
                              at: extra.range)
        }

        let close = expectClosing(.rightAngle, of: "Set type", openedAt: name.range,
                                  diagnostics: &diagnostics)
        return .set(element: element, range: name.range.union(close))
    }

    private mutating func parseMapType(diagnostics: inout DiagnosticBag) -> TypeSyntax {
        let name = take()
        take(.leftAngle)
        let key = parseType(diagnostics: &diagnostics)

        var value: TypeSyntax
        if take(.comma) != nil {
            value = parseType(diagnostics: &diagnostics)
        } else {
            diagnostics.error(.genericArity,
                              "'Map' takes two type arguments: a key and a value",
                              at: key.range,
                              notes: [.init(message: "write 'Map<\(SyntaxDumper.describe(key)), ValueType>'")])
            value = .missing(previousTokenEnd)
        }

        while take(.comma) != nil {
            let extra = parseType(diagnostics: &diagnostics)
            diagnostics.error(.genericArity,
                              "'Map' takes two type arguments",
                              at: extra.range)
        }

        let close = expectClosing(.rightAngle, of: "Map type", openedAt: name.range,
                                  diagnostics: &diagnostics)
        return .map(key: key, value: value, range: name.range.union(close))
    }

    /// Consume a closing bracket, reporting it as missing without consuming anything else.
    private mutating func expectClosing(_ punctuation: Punctuation,
                                        of context: String,
                                        openedAt open: SourceRange,
                                        diagnostics: inout DiagnosticBag) -> SourceRange {
        if let token = take(punctuation) {
            return token.range
        }
        diagnostics.error(.expectedType,
                          "expected '\(punctuation.rawValue)' to close this \(context)",
                          at: previousTokenEnd,
                          notes: [.init(message: "the \(context) starts here", range: open)])
        return previousTokenEnd
    }
}
