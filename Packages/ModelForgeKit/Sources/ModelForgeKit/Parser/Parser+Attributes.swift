import Foundation

extension Parser {

    /// `attribute = "@" IDENT ( "(" argumentList? ")" )?`
    ///
    /// Attributes are parsed structurally and validated later by `AttributeRegistry`, so
    /// an unknown attribute is a semantic problem with a suggestion rather than a syntax
    /// error that derails the declaration.
    mutating func parseAttribute(diagnostics: inout DiagnosticBag) -> AttributeSyntax? {
        guard let atSign = take(.at) else { return nil }

        guard let name = token.identifierText else {
            diagnostics.error(.expectedName,
                              "expected an attribute name after '@', found \(token.describedForDiagnostic)",
                              at: token.range)
            return nil
        }
        let nameToken = take()
        let identifier = IdentifierSyntax(text: name, range: nameToken.range)

        guard at(.leftParen) else {
            return AttributeSyntax(name: identifier, arguments: [],
                                   range: atSign.range.union(nameToken.range))
        }

        let open = take()
        var arguments: [AttributeArgumentSyntax] = []

        var argumentsFailed = false
        if !at(.rightParen) {
            repeat {
                guard let argument = parseAttributeArgument(diagnostics: &diagnostics) else {
                    argumentsFailed = true
                    break
                }
                arguments.append(argument)
            } while take(.comma) != nil
        }

        // An argument that failed to parse has already been reported. Skip ahead to the
        // closing paren rather than piling a less useful "expected ')'" on top of it.
        if argumentsFailed {
            while !atEnd, !at(.rightParen), !at(.rightBrace), !atDeclarationStart,
                  !token.isAtStartOfLine {
                take()
            }
        }

        var end = open.range
        if let close = take(.rightParen) {
            end = close.range
        } else {
            if !argumentsFailed {
                diagnostics.error(.invalidAttributeArguments,
                                  "expected ')' to close the arguments of '@\(name)'",
                                  at: previousTokenEnd,
                                  notes: [.init(message: "the argument list starts here", range: open.range)])
            }
            end = previousTokenEnd
        }

        return AttributeSyntax(name: identifier, arguments: arguments,
                               range: atSign.range.union(end))
    }

    /// `argument = literal | IDENT ":" literal`
    private mutating func parseAttributeArgument(diagnostics: inout DiagnosticBag) -> AttributeArgumentSyntax? {
        var label: IdentifierSyntax?
        if let text = token.identifierText, lookahead(1).is(.colon) {
            let identifier = take()
            take(.colon)
            label = IdentifierSyntax(text: text, range: identifier.range)
        }

        guard let value = parseLiteral(diagnostics: &diagnostics) else {
            return nil
        }

        let range = label.map { $0.range.union(value.range) } ?? value.range
        return AttributeArgumentSyntax(label: label, value: value, range: range)
    }

    /// `literal = STRING | INTEGER | FLOAT | "true" | "false" | "null" | "[" "]" | "{" "}" | "." IDENT`
    mutating func parseLiteral(diagnostics: inout DiagnosticBag) -> LiteralSyntax? {
        switch token.kind {
        case .string(let value):
            return .string(value, take().range)

        case .integer(let lexeme):
            return .integer(lexeme: lexeme, take().range)

        case .float(let lexeme):
            return .float(lexeme: lexeme, take().range)

        case .keyword(.true):
            return .boolean(true, take().range)

        case .keyword(.false):
            return .boolean(false, take().range)

        case .keyword(.null):
            return .null(take().range)

        case .punctuation(.leftBracket) where lookahead(1).is(.rightBracket):
            let open = take()
            let close = take()
            return .emptyList(open.range.union(close.range))

        case .punctuation(.leftBrace) where lookahead(1).is(.rightBrace):
            let open = take()
            let close = take()
            return .emptyMap(open.range.union(close.range))

        case .punctuation(.dot):
            let dot = take()
            guard let name = token.identifierText else {
                diagnostics.error(.expectedName,
                                  "expected an enum case name after '.', found \(token.describedForDiagnostic)",
                                  at: token.range)
                return nil
            }
            let nameToken = take()
            let identifier = IdentifierSyntax(text: name, range: nameToken.range)
            return .enumCase(identifier, dot.range.union(nameToken.range))

        default:
            diagnostics.error(.expectedLiteral,
                              "expected a value, found \(token.describedForDiagnostic)",
                              at: token.range)
            return nil
        }
    }
}
