import Testing
@testable import ModelForgeKit

/// The parser must never throw and never blank the previews. Each test here asserts two
/// things: that the right problem is reported at the right place, and — more importantly —
/// that the surrounding declarations still survive into the tree.
@Suite("Parser recovery")
struct ParserRecoveryTests {

    @Test("a missing closing brace is reported once and the next declaration survives")
    func missingClosingBrace() {
        let result = ParseSupport.parse("""
        model User {
            id: UUID

        enum Status {
            active
        }
        """)
        #expect(result.codes == [.expectedRightBrace])
        #expect(result.declarationNames == ["User", "Status"])
        #expect(ParseSupport.model(result, named: "User")?.fields.map(\.name.text) == ["id"])
    }

    @Test("typing a new declaration above an existing one does not swallow it")
    func declarationKeywordClosesPreviousBody() {
        // The shape you get halfway through adding a model above another.
        let result = ParseSupport.parse("""
        model Draft {
        model User {
            id: UUID
        }
        """)
        #expect(result.codes == [.expectedRightBrace])
        #expect(result.declarationNames == ["Draft", "User"])
    }

    @Test("a field missing its colon is dropped and the next field still parses")
    func fieldMissingColon() {
        let result = ParseSupport.parse("""
        model User {
            id UUID
            name: String
        }
        """)
        #expect(result.positions == ["2:7 expectedColon"])
        // The malformed field is dropped rather than guessed at, so the generated code
        // never declares a field the author didn't finish writing.
        #expect(ParseSupport.model(result, named: "User")?.fields.map(\.name.text) == ["name"])
    }

    @Test("a broken type yields a placeholder without damaging the next line")
    func brokenTypeDoesNotCascade() {
        let result = ParseSupport.parse("""
        model User {
            id:
            name: String
        }
        """)
        #expect(result.codes == [.expectedType])
        let fields = ParseSupport.model(result, named: "User")?.fields
        #expect(fields?.map(\.name.text) == ["id", "name"])
        #expect(fields?.first?.type.containsMissing == true)
    }

    @Test("an unclosed container type stops at the end of its line")
    func unclosedContainerType() {
        let result = ParseSupport.parse("""
        model User {
            tags: [String
            name: String
        }
        """)
        #expect(result.codes.contains(.expectedType))
        #expect(ParseSupport.model(result, named: "User")?.fields.contains { $0.name.text == "name" } == true)
    }

    @Test("junk at the top level is reported once and skipped")
    func junkAtTopLevel() {
        let result = ParseSupport.parse("""
        model A { id: UUID }
        this is not valid at all
        model B { id: UUID }
        """)
        #expect(result.codes == [.expectedDeclaration])
        #expect(result.declarationNames == ["A", "B"])
    }

    @Test("a declaration with no name still parses its body")
    func missingDeclarationName() {
        let result = ParseSupport.parse("""
        model {
            id: UUID
        }
        """)
        #expect(result.codes == [.expectedName])
        #expect(result.document.declarations.count == 1)
        #expect(result.document.declarations.first?.name.isMissing == true)
        #expect(ParseSupport.model(result, named: "")?.fields.map(\.name.text) == ["id"])
    }

    @Test("a declaration whose body has not been written yet is treated as empty")
    func missingBody() {
        let result = ParseSupport.parse("""
        model User
        model Other { id: UUID }
        """)
        #expect(result.codes == [.expectedLeftBrace])
        #expect(result.declarationNames == ["User", "Other"])
        #expect(ParseSupport.model(result, named: "User")?.fields.isEmpty == true)
    }

    @Test("a union case missing its payload is reported and the next case survives")
    func unionCaseMissingPayload() {
        let result = ParseSupport.parse("""
        union Event {
            message
            image(ImageEvent)
        }
        """)
        #expect(result.codes == [.expectedPayload])
        if case .union(let union)? = result.document.declarations.first {
            #expect(union.cases.map(\.name.text) == ["image"])
        } else {
            Issue.record("expected a union declaration")
        }
    }

    @Test("generic arity problems are reported without losing the member list")
    func genericArity() {
        let result = ParseSupport.parse("""
        model A {
            bad: Map<String>
            worse: Set<A, B>
            fine: String
        }
        """)
        #expect(result.codes == [.genericArity, .genericArity])
        #expect(ParseSupport.model(result, named: "A")?.fields.map(\.name.text) == ["bad", "worse", "fine"])
    }

    @Test("every prefix of a valid document parses without throwing")
    func everyPrefixParses() {
        // Simulates typing the document one character at a time. Nothing here may trap,
        // and there must always be a tree to generate previews from.
        let source = """
        /// A user.
        model User {
            @json("user_id")
            id: UUID
            tags: [String] = []
        }

        enum Status { active }
        """
        for length in 0...source.count {
            let prefix = String(source.prefix(length))
            let result = ParseSupport.parse(prefix)
            #expect(result.document.declarations.count >= 0)
        }
    }

    @Test("renders a diagnostic in the proposal's caret format")
    func rendersCaretFormat() {
        let result = ParseSupport.parse("""
        model User {
            id UUID
        }
        """)
        // Four spaces of gutter are added to the source line, and the caret lands on the
        // space after 'id' — exactly where the missing ':' belongs.
        let expected = [
            "test.model:2:7",
            "",
            "        id UUID",
            "          ^",
            "",
            "error: expected ':' after field name 'id'",
            "help: fields are written as 'name: Type'"
        ].joined(separator: "\n")
        #expect(result.rendered == expected)
    }
}
