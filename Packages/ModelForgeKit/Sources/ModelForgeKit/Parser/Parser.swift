import Foundation

// Grammar, following §13 of the DSL proposal with `import` and `config` removed:
//
//   document        = declaration* EOF ;
//   declaration     = docComment* attribute*
//                     ( modelDecl | enumDecl | unionDecl | typealiasDecl ) ;
//   modelDecl       = "model" IDENT "{" fieldDecl* "}" ;
//   fieldDecl       = docComment* attribute* IDENT ":" type defaultValue? ;
//   enumDecl        = "enum" IDENT "{" enumCase* "}" ;
//   enumCase        = docComment* attribute* IDENT ;
//   unionDecl       = "union" IDENT "{" unionCase* "}" ;
//   unionCase       = docComment* attribute* IDENT "(" type ")" ;
//   typealiasDecl   = "typealias" IDENT "=" type ;
//   type            = primaryType "?"* ;
//   primaryType     = IDENT | "[" type "]" | "Set" "<" type ">" | "Map" "<" type "," type ">" ;
//   defaultValue    = "=" literal ;
//   attribute       = "@" IDENT ( "(" argumentList? ")" )? ;
//   argumentList    = argument ( "," argument )* ;
//   argument        = literal | IDENT ":" literal ;
//   literal         = STRING | INTEGER | FLOAT | "true" | "false" | "null"
//                   | "[" "]" | "{" "}" | "." IDENT ;

/// Recursive descent over a token stream.
///
/// The parser **never throws and never backtracks more than one token**. Everything about
/// its error handling exists to serve one requirement: the previews must keep rendering
/// while the user is in the middle of typing. A half-written declaration produces one
/// diagnostic and a partial tree, not an exception and a blank pane.
public struct Parser {

    private var cursor: TokenCursor
    private let file: SourceFileID

    public static func parse(_ tokens: [Token],
                             file: SourceFileID,
                             diagnostics: inout DiagnosticBag) -> DocumentSyntax {
        var parser = Parser(cursor: TokenCursor(tokens), file: file)
        return parser.parseDocument(diagnostics: &diagnostics)
    }

    /// Lex and parse in one step.
    public static func parse(_ source: SourceFile,
                             diagnostics: inout DiagnosticBag) -> DocumentSyntax {
        let tokens = Lexer.tokenize(source, diagnostics: &diagnostics)
        return parse(tokens, file: source.id, diagnostics: &diagnostics)
    }

    private init(cursor: TokenCursor, file: SourceFileID) {
        self.cursor = cursor
        self.file = file
    }

    // MARK: Document

    private mutating func parseDocument(diagnostics: inout DiagnosticBag) -> DocumentSyntax {
        var declarations: [DeclarationSyntax] = []

        while !cursor.isAtEnd {
            let trivia = parseTrivia(diagnostics: &diagnostics)

            guard let keyword = cursor.current.keyword, keyword.startsDeclaration else {
                // Nothing here starts a declaration. Report once, then skip to something
                // that does so a single stray line can't cascade.
                diagnostics.error(.expectedDeclaration,
                                  "expected a declaration, found \(cursor.current.describedForDiagnostic)",
                                  at: cursor.current.range,
                                  notes: [.init(message: "declarations begin with 'model', 'enum', 'union' or 'typealias'")])
                skipToNextDeclaration()
                continue
            }

            if let declaration = parseDeclaration(keyword: keyword,
                                                  trivia: trivia,
                                                  diagnostics: &diagnostics) {
                declarations.append(declaration)
            }
        }

        return DocumentSyntax(file: file, declarations: declarations)
    }

    private mutating func parseDeclaration(keyword: Keyword,
                                           trivia: Trivia,
                                           diagnostics: inout DiagnosticBag) -> DeclarationSyntax? {
        switch keyword {
        case .model:
            parseModel(trivia: trivia, diagnostics: &diagnostics).map(DeclarationSyntax.model)
        case .enum:
            parseEnum(trivia: trivia, diagnostics: &diagnostics).map(DeclarationSyntax.enum)
        case .union:
            parseUnion(trivia: trivia, diagnostics: &diagnostics).map(DeclarationSyntax.union)
        case .typealias:
            parseTypeAlias(trivia: trivia, diagnostics: &diagnostics).map(DeclarationSyntax.typeAlias)
        default:
            nil
        }
    }

    // MARK: Trivia

    /// Leading documentation comments and attributes, in the order written.
    struct Trivia {
        var documentation: [DocCommentSyntax] = []
        var attributes: [AttributeSyntax] = []
        var start: SourceRange?

        var isEmpty: Bool { documentation.isEmpty && attributes.isEmpty }
    }

    mutating func parseTrivia(diagnostics: inout DiagnosticBag) -> Trivia {
        var trivia = Trivia()
        while true {
            if case .docComment(let text) = cursor.current.kind {
                let token = cursor.advance()
                trivia.start = trivia.start ?? token.range
                trivia.documentation.append(DocCommentSyntax(text: text, range: token.range))
                continue
            }
            if cursor.check(.at) {
                let attributeStart = cursor.current.range
                if let attribute = parseAttribute(diagnostics: &diagnostics) {
                    trivia.start = trivia.start ?? attributeStart
                    trivia.attributes.append(attribute)
                }
                continue
            }
            break
        }
        return trivia
    }

    // MARK: Names

    /// A declaration or member name. A missing one is synthesised so the rest of the
    /// declaration still parses and still contributes to the previews.
    mutating func parseName(context: String, diagnostics: inout DiagnosticBag) -> IdentifierSyntax {
        if let text = cursor.current.identifierText {
            let token = cursor.advance()
            return IdentifierSyntax(text: text, range: token.range)
        }
        diagnostics.error(.expectedName,
                          "expected a name for this \(context), found \(cursor.current.describedForDiagnostic)",
                          at: cursor.current.range)
        return IdentifierSyntax(text: "", range: cursor.endOfPreviousToken)
    }

    // MARK: Recovery

    /// Skip forward to the next thing that could begin a declaration.
    mutating func skipToNextDeclaration() {
        while !cursor.isAtEnd {
            if cursor.isAtDeclarationStart { return }
            if case .docComment = cursor.current.kind, cursor.current.isAtStartOfLine { return }
            cursor.advance()
        }
    }

    /// Discard whatever is left on the current line.
    ///
    /// The canonical style is one member per line, so this resynchronises within a single
    /// line and a broken field never damages the one below it. It returns immediately when
    /// the cursor already sits at a line start, so a member that failed *before* consuming
    /// anything does not eat the following line — see `skipMalformedMember`.
    mutating func skipToNextLineOrCloseBrace() {
        while !cursor.isAtEnd {
            if cursor.current.isAtStartOfLine { return }
            if cursor.check(.rightBrace) { return }
            if cursor.isAtDeclarationStart { return }
            cursor.advance()
        }
    }

    /// Discard a member that could not even be started.
    ///
    /// Always consumes at least one token, which is what guarantees the member loops
    /// terminate: a loop whose body reports an error without consuming would spin forever.
    mutating func skipMalformedMember() {
        if !cursor.isAtEnd, !cursor.check(.rightBrace), !cursor.isAtDeclarationStart {
            cursor.advance()
        }
        skipToNextLineOrCloseBrace()
    }

    /// Whether the cursor has moved onto a new line since the token before it.
    ///
    /// A type or value may not begin on the line after the `:` or `=` that introduces it.
    /// Enforcing that is what stops `id:` with nothing after it from stealing the next
    /// field's name as its type.
    var isOnNewLine: Bool {
        cursor.current.isAtStartOfLine
    }

    /// Whether a member list should stop here.
    ///
    /// A declaration keyword appearing where a member was expected means the previous
    /// declaration's closing brace is missing — the common shape of typing a new
    /// declaration above an existing one.
    var isAtEndOfMemberList: Bool {
        cursor.isAtEnd || cursor.check(.rightBrace) || cursor.isAtDeclarationStart
    }

    /// Consume the body's closing brace, or report that it is missing.
    mutating func closeBody(of context: String,
                            openedAt open: SourceRange,
                            diagnostics: inout DiagnosticBag) -> SourceRange {
        if let brace = cursor.match(.rightBrace) {
            return brace.range
        }
        diagnostics.error(.expectedRightBrace,
                          "expected '}' to close this \(context)",
                          at: cursor.endOfPreviousToken,
                          notes: [.init(message: "the \(context) starts here", range: open)])
        return cursor.endOfPreviousToken
    }

    /// Consume the body's opening brace. Returns `nil` when it is absent and the body
    /// should be treated as empty.
    mutating func openBody(of context: String,
                           diagnostics: inout DiagnosticBag) -> SourceRange? {
        if let brace = cursor.match(.leftBrace) {
            return brace.range
        }
        diagnostics.error(.expectedLeftBrace,
                          "expected '{' after the \(context) name, found \(cursor.current.describedForDiagnostic)",
                          at: cursor.current.range)
        // The author simply hasn't written the body yet. Treating it as empty is far less
        // disruptive than swallowing whatever follows into a body that was never opened.
        return nil
    }

    // MARK: Cursor access for the extensions

    var token: Token { cursor.current }

    @discardableResult
    mutating func take() -> Token { cursor.advance() }

    @discardableResult
    mutating func take(_ punctuation: Punctuation) -> Token? { cursor.match(punctuation) }

    @discardableResult
    mutating func take(_ keyword: Keyword) -> Token? { cursor.match(keyword) }

    func at(_ punctuation: Punctuation) -> Bool { cursor.check(punctuation) }

    func at(_ keyword: Keyword) -> Bool { cursor.check(keyword) }

    func lookahead(_ distance: Int) -> Token { cursor.peek(distance) }

    var atEnd: Bool { cursor.isAtEnd }

    var previousTokenEnd: SourceRange { cursor.endOfPreviousToken }

    var atDeclarationStart: Bool { cursor.isAtDeclarationStart }
}
