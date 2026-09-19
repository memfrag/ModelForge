import Testing
@testable import ModelForgeKit

@Suite("Lexer")
struct LexerTests {

    private func lex(_ source: String) -> (tokens: [Token], diagnostics: [Diagnostic]) {
        let file = SourceFile(id: SourceFileID(0), name: "test.model", text: source)
        var bag = DiagnosticBag()
        let tokens = Lexer.tokenize(file, diagnostics: &bag)
        return (tokens, bag.sorted())
    }

    @Test("tokenizes the field example from the proposal")
    func tokenizesField() {
        let (tokens, diagnostics) = lex("email: String?")
        #expect(diagnostics.isEmpty)
        #expect(tokens.map(\.kind) == [
            .identifier("email"),
            .punctuation(.colon),
            .identifier("String"),
            .punctuation(.question),
            .endOfFile
        ])
    }

    @Test("reports exact source ranges")
    func reportsRanges() {
        let (tokens, _) = lex("model User {\n    id: UUID\n}")
        let id = tokens.first { $0.identifierText == "id" }
        #expect(id?.range.start.line == 2)
        #expect(id?.range.start.column == 5)
        #expect(id?.range.utf16Range == 17..<19)
        #expect(id?.isAtStartOfLine == true)
        #expect(tokens.first { $0.identifierText == "UUID" }?.isAtStartOfLine == false)
    }

    @Test("distinguishes keywords from identifiers")
    func distinguishesKeywords() {
        let (tokens, _) = lex("model enum union typealias true false null Set Map")
        #expect(tokens.compactMap(\.keyword) == [.model, .enum, .union, .typealias, .true, .false, .null])
        // Set and Map stay identifiers; the parser recognises them contextually.
        #expect(tokens.compactMap(\.identifierText) == ["Set", "Map"])
    }

    @Test("import and config are no longer keywords")
    func importAndConfigAreIdentifiers() {
        let (tokens, _) = lex("import config")
        #expect(tokens.compactMap(\.identifierText) == ["import", "config"])
        #expect(tokens.compactMap(\.keyword).isEmpty)
    }

    @Test("strips the marker and one space from doc comments")
    func stripsDocComments() {
        let (tokens, _) = lex("/// A registered user.\n///No space.\n// Not documentation.")
        let docs: [String] = tokens.compactMap {
            if case .docComment(let text) = $0.kind { return text }
            return nil
        }
        #expect(docs == ["A registered user.", "No space."])
        #expect(tokens.contains { if case .lineComment = $0.kind { return true } else { return false } })
    }

    @Test("keeps numeric lexemes verbatim so output stays byte-stable")
    func keepsNumericLexemes() {
        let (tokens, _) = lex("0 -1 1.50 1e9 1.5E-3 1_000")
        #expect(tokens.compactMap { token -> String? in
            switch token.kind {
            case .integer(let lexeme): "int:\(lexeme)"
            case .float(let lexeme): "float:\(lexeme)"
            default: nil
            }
        } == ["int:0", "int:-1", "float:1.50", "float:1e9", "float:1.5E-3", "int:1_000"])
    }

    @Test("a dot after a number starts an enum case, not a float")
    func dotAfterNumberIsNotAFloat() {
        let (tokens, _) = lex("1.active")
        #expect(tokens.map(\.kind) == [
            .integer(lexeme: "1"),
            .punctuation(.dot),
            .identifier("active"),
            .endOfFile
        ])
    }

    @Test("decodes string escapes")
    func decodesEscapes() {
        let (tokens, diagnostics) = lex(#""user_id" "a\"b" "tab\there""#)
        #expect(diagnostics.isEmpty)
        #expect(tokens.compactMap { token -> String? in
            if case .string(let value) = token.kind { return value }
            return nil
        } == ["user_id", "a\"b", "tab\there"])
    }

    @Test("an unterminated string stops at the newline and reports once")
    func unterminatedStringStopsAtNewline() {
        let (tokens, diagnostics) = lex("@json(\"oops\nid: UUID")
        #expect(diagnostics.map(\.code) == [.unterminatedString])
        // The next line still lexes normally, so only one line is damaged.
        #expect(tokens.contains { $0.identifierText == "id" })
        #expect(tokens.contains { $0.identifierText == "UUID" })
    }

    @Test("an unknown character yields a token and a diagnostic, never a throw")
    func unknownCharacterRecovers() {
        let (tokens, diagnostics) = lex("id: UUID ` name: String")
        #expect(diagnostics.map(\.code) == [.invalidCharacter])
        #expect(tokens.contains { $0.identifierText == "name" })
    }

    @Test("lexing a line in isolation matches lexing the whole file")
    func lineLexingMatchesWholeFile() {
        let source = """
        /// Doc
        model User {
            @json("user_id")
            id: UUID = 3
            name: String?
        }
        """
        let file = SourceFile(id: SourceFileID(0), name: "test.model", text: source)
        var bag = DiagnosticBag()
        let whole = Lexer.tokenize(file, diagnostics: &bag).filter { !$0.isEndOfFile }

        var perLine: [Token] = []
        for line in 1...file.lineTable.lineCount {
            let range = file.lineTable.range(ofLine: line)
            perLine += Lexer.tokenize(file, in: range)
        }

        #expect(whole == perLine)
    }
}
