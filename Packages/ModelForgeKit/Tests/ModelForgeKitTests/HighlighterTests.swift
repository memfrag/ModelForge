import Testing
@testable import ModelForgeKit

@Suite("Highlighting")
struct HighlighterTests {

    private func dslSpans(_ source: String) -> [(HighlightKind, String)] {
        let file = SourceFile(id: SourceFileID(0), name: "t.model", text: source)
        var bag = DiagnosticBag()
        let tokens = Lexer.tokenize(file, diagnostics: &bag)
        return DSLHighlightClassifier.spans(for: tokens).map { span in
            (span.kind, String(decoding: Array(file.utf16[span.range]), as: UTF16.self))
        }
    }

    private func find(_ spans: [(HighlightKind, String)], _ text: String) -> HighlightKind? {
        spans.first { $0.1 == text }?.0
    }

    @Test("classifies a model declaration from the real lexer")
    func classifiesModel() {
        let spans = dslSpans("""
        /// Doc.
        model User {
            @json("user_id")
            id: UUID
            tags: [String]
            status: Status = .active
        }
        """)
        #expect(find(spans, "model") == .keyword)
        #expect(find(spans, "User") == .declarationName)
        #expect(find(spans, "json") == .attribute)
        #expect(find(spans, "\"user_id\"") == .string)
        #expect(find(spans, "id") == .fieldName)
        #expect(find(spans, "UUID") == .typeName)
        #expect(find(spans, "String") == .typeName)
        #expect(find(spans, "active") == .enumCase)
        #expect(find(spans, "/// Doc.") == .docComment)
    }

    @Test("a type alias colours its target as a type, not a value")
    func typeAliasTarget() {
        let spans = dslSpans("typealias UserID = UUID")
        #expect(find(spans, "UserID") == .declarationName)
        #expect(find(spans, "UUID") == .typeName)
    }

    @Test("nested container arguments are types")
    func nestedContainers() {
        let spans = dslSpans("model A { m: Map<String, [User]> }")
        #expect(find(spans, "Map") == .typeName)
        #expect(find(spans, "String") == .typeName)
        #expect(find(spans, "User") == .typeName)
        #expect(find(spans, "m") == .fieldName)
    }

    @Test("a union payload is a type")
    func unionPayload() {
        let spans = dslSpans("union U { card(Card) }")
        #expect(find(spans, "card") == .fieldName)
        #expect(find(spans, "Card") == .typeName)
    }

    @Test("a field on the line after a default is not mistaken for a type")
    func stateResetsPerLine() {
        let spans = dslSpans("""
        model A {
            a: Bool = false
            b: String
        }
        """)
        #expect(find(spans, "b") == .fieldName)
    }

    @Test("spans line up with the source they describe")
    func spansAreAccurate() {
        let source = "model User { id: UUID }"
        let file = SourceFile(id: SourceFileID(0), name: "t.model", text: source)
        var bag = DiagnosticBag()
        let spans = DSLHighlightClassifier.spans(for: Lexer.tokenize(file, diagnostics: &bag))
        for span in spans {
            #expect(span.range.lowerBound >= 0)
            #expect(span.range.upperBound <= file.utf16.count)
            #expect(span.range.lowerBound < span.range.upperBound)
        }
    }

    // MARK: Generated code

    @Test("highlights generated Swift")
    func highlightsSwift() {
        let code = """
        // Generated
        struct User: Codable {
            let id: UUID
            let name: String = "x"
        }
        """
        let spans = GeneratedCodeLexer.spans(in: code, language: .swift, knownTypeNames: ["User"])
        let text = Array(code.utf16)
        func kind(_ word: String) -> HighlightKind? {
            spans.first { String(decoding: Array(text[$0.range]), as: UTF16.self) == word }?.kind
        }
        #expect(kind("struct") == .keyword)
        #expect(kind("User") == .typeName)
        #expect(kind("Codable") == .typeName)
        #expect(kind("id") == .fieldName)
        #expect(kind("\"x\"") == .string)
        #expect(kind("// Generated") == .comment)
    }

    @Test("highlights generated Kotlin, including annotations and constants")
    func highlightsKotlin() {
        let code = """
        /** Doc */
        @Serializable
        data class User(
            @SerialName("user_id")
            val id: Uuid = 1.0f,
        )
        enum class S { ACTIVE }
        """
        let spans = GeneratedCodeLexer.spans(in: code, language: .kotlin, knownTypeNames: ["User"])
        let text = Array(code.utf16)
        func kind(_ word: String) -> HighlightKind? {
            spans.first { String(decoding: Array(text[$0.range]), as: UTF16.self) == word }?.kind
        }
        #expect(kind("@Serializable") == .attribute)
        #expect(kind("@SerialName") == .attribute)
        #expect(kind("data") == .keyword)
        #expect(kind("val") == .keyword)
        #expect(kind("Uuid") == .typeName)
        #expect(kind("1.0f") == .number)
        #expect(kind("ACTIVE") == .enumCase)
        #expect(kind("/** Doc */") == .docComment)
    }

    @Test("a backtick-escaped name is still classified by its bare spelling")
    func escapedNames() {
        let code = "val `object`: String"
        let spans = GeneratedCodeLexer.spans(in: code, language: .kotlin)
        let text = Array(code.utf16)
        let escaped = spans.first { String(decoding: Array(text[$0.range]), as: UTF16.self) == "`object`" }
        #expect(escaped?.kind == .fieldName)
    }

    @Test("every generated fixture highlights without dropping or overlapping text")
    func fixtureCoverage() {
        let output = CompilePipeline.run(files: Snapshot.project("EndToEnd"), configuration: .default)
        for file in output.generated.files {
            let spans = GeneratedCodeLexer.spans(in: file.contents, language: file.language)
            var previousEnd = 0
            for span in spans {
                #expect(span.range.lowerBound >= previousEnd)
                previousEnd = span.range.upperBound
            }
            #expect(previousEnd <= Array(file.contents.utf16).count)
        }
    }
}
