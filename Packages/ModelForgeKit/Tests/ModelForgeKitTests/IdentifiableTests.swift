import Testing
@testable import ModelForgeKit

/// `@identifiable` is Swift-only — Kotlin has no equivalent — and it cannot be a blanket
/// conformance like `Codable`, because a model with no suitable field would produce Swift
/// that does not compile. So every rejection here stands in for a compile error the user
/// would otherwise have hit in Xcode.
@Suite("Identifiable")
struct IdentifiableTests {

    private func generate(_ source: String) -> CompilePipeline.Output {
        var configuration = ProjectConfiguration.default
        configuration.kotlin.package = "com.example.models"
        return CompilePipeline.run(
            files: [SourceFile(id: SourceFileID(0), name: "test.model", text: source)],
            configuration: configuration)
    }

    private func swift(_ source: String) -> String {
        generate(source).generated.files.first { $0.language == .swift && $0.sourceFile != nil }?.contents ?? ""
    }

    private func kotlin(_ source: String) -> String {
        generate(source).generated.files.first { $0.language == .kotlin && $0.sourceFile != nil }?.contents ?? ""
    }

    // MARK: Conforming

    @Test("a model with an id field just conforms")
    func conformsUsingIDField() {
        let output = swift("@identifiable\nmodel User { id: UUID\n name: String }")
        #expect(output.contains("struct User: Identifiable, Codable, Equatable, Sendable {"))
        // Nothing extra is needed: the stored property already satisfies the protocol.
        #expect(!output.contains("var id:"))
    }

    @Test("naming another field generates the bridging property")
    func bridgesANamedField() {
        let output = swift("@identifiable(\"code\")\nmodel Country { code: String\n name: String }")
        #expect(output.contains("struct Country: Identifiable,"))
        #expect(output.contains("var id: String { code }"))
    }

    @Test("a model without the attribute is untouched")
    func leavesOtherModelsAlone() {
        let output = swift("model Plain { name: String }")
        #expect(output.contains("struct Plain: Codable, Equatable, Sendable {"))
        #expect(!output.contains("Identifiable"))
    }

    @Test("Kotlin ignores it entirely")
    func kotlinIsUnaffected() {
        let output = kotlin("@identifiable(\"code\")\nmodel Country { code: String }")
        #expect(output.contains("data class Country("))
        #expect(!output.lowercased().contains("identifiable"))
    }

    @Test("it survives alongside the other conformance settings")
    func respectsConfiguration() {
        var configuration = ProjectConfiguration.default
        configuration.kotlin.package = "com.example.models"
        configuration.swift.hashable = true
        configuration.swift.sendable = false
        let output = CompilePipeline.run(
            files: [SourceFile(id: SourceFileID(0), name: "t.model",
                               text: "@identifiable\nmodel A { id: UUID }")],
            configuration: configuration)
            .generated.files.first { $0.language == .swift && $0.sourceFile != nil }!.contents
        #expect(output.contains("struct A: Identifiable, Codable, Hashable {"))
    }

    // MARK: Refusing

    @Test("refuses a model with no id field, listing what it does have")
    func refusesWithoutAnIDField() {
        let result = AnalyzeSupport.analyze("@identifiable\nmodel A { name: String\n slug: String }")
        #expect(result.codes == [.missingIdentityField])
        #expect(result.helps.contains { $0.contains("@identifiable(\"fieldName\")") })
        #expect(result.helps.contains { $0.contains("name, slug") })
    }

    @Test("refuses an unknown field name, with a suggestion")
    func refusesUnknownField() {
        let result = AnalyzeSupport.analyze("@identifiable(\"cod\")\nmodel B { code: String }")
        #expect(result.codes == [.missingIdentityField])
        #expect(result.helps.contains("did you mean 'code'?"))
    }

    @Test("refuses a bridging property that would collide with a real field")
    func refusesCollisionWithExistingID() {
        // Generating `var id` beside `let id` would not compile.
        let result = AnalyzeSupport.analyze("@identifiable(\"code\")\nmodel C { id: UUID\n code: String }")
        #expect(result.codes == [.missingIdentityField])
        #expect(result.helps.contains { $0.contains("no argument") })
    }

    @Test("refuses it on anything that is not a model")
    func refusesOnNonModels() {
        for source in ["@identifiable\nenum E { a }",
                       "@identifiable\nunion U { a(M) }\nmodel M { id: UUID }",
                       "@identifiable\ntypealias T = UUID"] {
            let result = AnalyzeSupport.analyze(source)
            #expect(result.codes.contains(.attributeNotAllowedHere), "for: \(source)")
        }
    }

    @Test("a refused model still generates, just without the conformance")
    func refusalDoesNotBlockPreviews() {
        let output = swift("@identifiable\nmodel A { name: String }")
        #expect(output.contains("struct A: Codable, Equatable, Sendable {"))
        #expect(!output.contains("Identifiable"))
    }
}
