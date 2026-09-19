import Foundation

extension Parser {

    // MARK: Model

    /// `modelDecl = "model" IDENT "{" fieldDecl* "}"`
    mutating func parseModel(trivia: Trivia, diagnostics: inout DiagnosticBag) -> ModelSyntax? {
        let keyword = take()
        let start = trivia.start ?? keyword.range
        let name = parseName(context: "model", diagnostics: &diagnostics)

        guard let open = openBody(of: "model", diagnostics: &diagnostics) else {
            return ModelSyntax(documentation: trivia.documentation,
                               attributes: trivia.attributes,
                               name: name, fields: [],
                               range: start.union(name.range))
        }

        var fields: [FieldSyntax] = []
        while !isAtEndOfMemberList {
            let memberTrivia = parseTrivia(diagnostics: &diagnostics)
            if isAtEndOfMemberList { break }
            if let field = parseField(trivia: memberTrivia, diagnostics: &diagnostics) {
                fields.append(field)
            }
        }

        let close = closeBody(of: "model", openedAt: open, diagnostics: &diagnostics)
        return ModelSyntax(documentation: trivia.documentation,
                           attributes: trivia.attributes,
                           name: name, fields: fields,
                           range: start.union(close))
    }

    /// `fieldDecl = docComment* attribute* IDENT ":" type defaultValue?`
    ///
    /// A field missing its colon is dropped entirely rather than guessed at: a half-typed
    /// line shouldn't invent a field that the generated code then declares.
    private mutating func parseField(trivia: Trivia,
                                     diagnostics: inout DiagnosticBag) -> FieldSyntax? {
        let start = trivia.start ?? token.range

        guard let fieldName = token.identifierText else {
            diagnostics.error(.expectedName,
                              "expected a field name, found \(token.describedForDiagnostic)",
                              at: token.range)
            skipMalformedMember()
            return nil
        }
        let nameToken = take()
        let name = IdentifierSyntax(text: fieldName, range: nameToken.range)

        guard take(.colon) != nil else {
            diagnostics.error(.expectedColon,
                              "expected ':' after field name '\(fieldName)'",
                              at: previousTokenEnd,
                              notes: [.init(message: "fields are written as 'name: Type'")])
            skipToNextLineOrCloseBrace()
            return nil
        }

        let type = parseMemberType(after: "':'", diagnostics: &diagnostics)

        var defaultValue: LiteralSyntax?
        if take(.equals) != nil {
            if isOnNewLine {
                diagnostics.error(.expectedLiteral,
                                  "expected a value after '='",
                                  at: previousTokenEnd)
            } else {
                defaultValue = parseLiteral(diagnostics: &diagnostics)
            }
        }

        let end = defaultValue?.range ?? type.range
        let field = FieldSyntax(documentation: trivia.documentation,
                                attributes: trivia.attributes,
                                name: name, type: type,
                                defaultValue: defaultValue,
                                range: start.union(end))

        recoverToNextMember(after: "field", diagnostics: &diagnostics)
        return field
    }

    // MARK: Enum

    /// `enumDecl = "enum" IDENT "{" enumCase* "}"`
    mutating func parseEnum(trivia: Trivia, diagnostics: inout DiagnosticBag) -> EnumSyntax? {
        let keyword = take()
        let start = trivia.start ?? keyword.range
        let name = parseName(context: "enum", diagnostics: &diagnostics)

        guard let open = openBody(of: "enum", diagnostics: &diagnostics) else {
            return EnumSyntax(documentation: trivia.documentation,
                              attributes: trivia.attributes,
                              name: name, cases: [],
                              range: start.union(name.range))
        }

        var cases: [EnumCaseSyntax] = []
        while !isAtEndOfMemberList {
            let caseTrivia = parseTrivia(diagnostics: &diagnostics)
            if isAtEndOfMemberList { break }

            let caseStart = caseTrivia.start ?? token.range
            guard let caseName = token.identifierText else {
                diagnostics.error(.expectedName,
                                  "expected an enum case name, found \(token.describedForDiagnostic)",
                                  at: token.range)
                skipMalformedMember()
                continue
            }
            let nameToken = take()
            cases.append(EnumCaseSyntax(documentation: caseTrivia.documentation,
                                        attributes: caseTrivia.attributes,
                                        name: IdentifierSyntax(text: caseName, range: nameToken.range),
                                        range: caseStart.union(nameToken.range)))

            // A comma between cases is accepted silently: it is a natural thing to type
            // and the canonical formatter would remove it anyway.
            take(.comma)
            recoverToNextMember(after: "enum case", diagnostics: &diagnostics)
        }

        let close = closeBody(of: "enum", openedAt: open, diagnostics: &diagnostics)
        return EnumSyntax(documentation: trivia.documentation,
                          attributes: trivia.attributes,
                          name: name, cases: cases,
                          range: start.union(close))
    }

    // MARK: Union

    /// `unionDecl = "union" IDENT "{" unionCase* "}"`
    mutating func parseUnion(trivia: Trivia, diagnostics: inout DiagnosticBag) -> UnionSyntax? {
        let keyword = take()
        let start = trivia.start ?? keyword.range
        let name = parseName(context: "union", diagnostics: &diagnostics)

        guard let open = openBody(of: "union", diagnostics: &diagnostics) else {
            return UnionSyntax(documentation: trivia.documentation,
                               attributes: trivia.attributes,
                               name: name, cases: [],
                               range: start.union(name.range))
        }

        var cases: [UnionCaseSyntax] = []
        while !isAtEndOfMemberList {
            let caseTrivia = parseTrivia(diagnostics: &diagnostics)
            if isAtEndOfMemberList { break }
            if let unionCase = parseUnionCase(trivia: caseTrivia, diagnostics: &diagnostics) {
                cases.append(unionCase)
            }
        }

        let close = closeBody(of: "union", openedAt: open, diagnostics: &diagnostics)
        return UnionSyntax(documentation: trivia.documentation,
                           attributes: trivia.attributes,
                           name: name, cases: cases,
                           range: start.union(close))
    }

    /// `unionCase = docComment* attribute* IDENT "(" type ")"`
    private mutating func parseUnionCase(trivia: Trivia,
                                         diagnostics: inout DiagnosticBag) -> UnionCaseSyntax? {
        let start = trivia.start ?? token.range

        guard let caseName = token.identifierText else {
            diagnostics.error(.expectedName,
                              "expected a union case name, found \(token.describedForDiagnostic)",
                              at: token.range)
            skipMalformedMember()
            return nil
        }
        let nameToken = take()
        let name = IdentifierSyntax(text: caseName, range: nameToken.range)

        guard take(.leftParen) != nil else {
            diagnostics.error(.expectedPayload,
                              "expected '(' after union case '\(caseName)'",
                              at: previousTokenEnd,
                              notes: [.init(message: "union cases carry a payload, written as 'case(PayloadModel)'")])
            skipToNextLineOrCloseBrace()
            return nil
        }

        let payload = parseMemberType(after: "'('", diagnostics: &diagnostics)

        var end = payload.range
        if let close = take(.rightParen) {
            end = close.range
        } else {
            diagnostics.error(.expectedPayload,
                              "expected ')' after the payload of '\(caseName)'",
                              at: previousTokenEnd)
            end = previousTokenEnd
        }

        take(.comma)
        let unionCase = UnionCaseSyntax(documentation: trivia.documentation,
                                        attributes: trivia.attributes,
                                        name: name, payload: payload,
                                        range: start.union(end))
        recoverToNextMember(after: "union case", diagnostics: &diagnostics)
        return unionCase
    }

    // MARK: Type alias

    /// `typealiasDecl = "typealias" IDENT "=" type`
    mutating func parseTypeAlias(trivia: Trivia,
                                 diagnostics: inout DiagnosticBag) -> TypeAliasSyntax? {
        let keyword = take()
        let start = trivia.start ?? keyword.range
        let name = parseName(context: "typealias", diagnostics: &diagnostics)

        guard take(.equals) != nil else {
            diagnostics.error(.unexpectedToken,
                              "expected '=' after 'typealias \(name.text)'",
                              at: previousTokenEnd,
                              notes: [.init(message: "type aliases are written as 'typealias Name = Type'")])
            return TypeAliasSyntax(documentation: trivia.documentation,
                                   attributes: trivia.attributes,
                                   name: name,
                                   target: .missing(previousTokenEnd),
                                   range: start.union(name.range))
        }

        let target = parseType(diagnostics: &diagnostics)
        return TypeAliasSyntax(documentation: trivia.documentation,
                               attributes: trivia.attributes,
                               name: name, target: target,
                               range: start.union(target.range))
    }

    // MARK: Shared recovery

    /// Parse a type that must begin on the current line.
    ///
    /// Without this, `id:` followed by a newline would consume the *next* field's name as
    /// its type, turning one unfinished line into two wrong ones.
    private mutating func parseMemberType(after introducer: String,
                                          diagnostics: inout DiagnosticBag) -> TypeSyntax {
        guard !isOnNewLine else {
            diagnostics.error(.expectedType,
                              "expected a type after \(introducer)",
                              at: previousTokenEnd)
            return .missing(previousTokenEnd)
        }
        return parseType(diagnostics: &diagnostics)
    }

    /// After a member parses successfully, decide whether what follows could begin
    /// another member.
    ///
    /// The grammar has no separator between members, so several may legitimately share a
    /// line — `enum Status { active suspended }` is valid. Only a token that cannot start
    /// a member at all is junk worth reporting.
    private mutating func recoverToNextMember(after context: String,
                                              diagnostics: inout DiagnosticBag) {
        if atEnd || at(.rightBrace) || atDeclarationStart { return }
        if token.identifierText != nil { return }
        if at(.at) { return }
        if case .docComment = token.kind { return }

        diagnostics.error(.unexpectedToken,
                          "unexpected \(token.describedForDiagnostic) after this \(context)",
                          at: token.range)
        skipMalformedMember()
    }
}
