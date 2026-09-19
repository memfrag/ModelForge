import Testing
@testable import ModelForgeKit

/// A closed enum fails the *whole payload* when a backend adds a case — that is what takes
/// a shipped app down, not the loss of one field. `@extensible` keeps the raw value and
/// round-trips it untouched, on both platforms, at the cost of exhaustive switching.
@Suite("Extensible enums")
struct ExtensibleEnumTests {

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

    private static let source = """
    @extensible
    enum Status {
        active
        @json("gone")
        deleted
    }
    """

    @Test("closed enums are unchanged")
    func closedEnumsAreUnchanged() {
        #expect(swift("enum Status { active }").contains("enum Status: String, Codable, Sendable {"))
        #expect(kotlin("enum Status { active }").contains("enum class Status {"))
    }

    @Test("Swift becomes a RawRepresentable struct, since an enum cannot hold an unknown case")
    func swiftBecomesAStruct() {
        let output = swift(Self.source)
        #expect(output.contains("struct Status: RawRepresentable, Codable, Hashable, Sendable {"))
        #expect(output.contains("let rawValue: String"))
        #expect(output.contains("static let active = Status(rawValue: \"active\")"))
        // A renamed case keeps its wire value as the constant's raw value.
        #expect(output.contains("static let deleted = Status(rawValue: \"gone\")"))
        // Coded as a bare string, not as an object wrapping rawValue.
        #expect(output.contains("try decoder.singleValueContainer().decode(String.self)"))
        #expect(output.contains("try container.encode(self.rawValue)"))
    }

    @Test("Kotlin becomes a value class, which serializes as its underlying string")
    func kotlinBecomesAValueClass() {
        let output = kotlin(Self.source)
        #expect(output.contains("@JvmInline"))
        #expect(output.contains("value class Status(val rawValue: String) {"))
        #expect(output.contains("val ACTIVE = Status(\"active\")"))
        #expect(output.contains("val DELETED = Status(\"gone\")"))
        // No @SerialName: an inline class is serialized as its value, so the constant name
        // never reaches the wire.
        #expect(!output.contains("@SerialName"))
    }

    @Test("an extensible enum still works as a field type and as a default")
    func usableAsAFieldAndDefault() {
        let output = generate("""
        @extensible
        enum Status { active }
        model A { status: Status = .active }
        """)
        #expect(output.result.diagnostics.isEmpty)
        let swift = output.generated.files.first { $0.language == .swift && $0.sourceFile != nil }!.contents
        #expect(swift.contains("?? .active"))
        let kotlin = output.generated.files.first { $0.language == .kotlin && $0.sourceFile != nil }!.contents
        #expect(kotlin.contains("val status: Status = Status.ACTIVE"))
    }

    @Test("an empty extensible enum is still valid")
    func emptyIsValid() {
        let output = generate("@extensible\nenum Status { }")
        #expect(output.result.diagnostics.isEmpty)
        #expect(output.generated.files.first { $0.language == .kotlin && $0.sourceFile != nil }?
            .contents.contains("value class Status(val rawValue: String)") == true)
    }

    @Test("it is recorded in the IR, so the two emitters cannot disagree")
    func appearsInTheIR() {
        let result = AnalyzeSupport.analyze(Self.source)
        guard case .enum(let definition)? = result.module["Status"] else {
            Issue.record("expected an enum"); return
        }
        #expect(definition.isExtensible)
        #expect(result.dump.contains("enum Status extensible"))
    }

    @Test("it belongs on enums and nowhere else")
    func onlyOnEnums() {
        for source in ["@extensible\nmodel M { id: UUID }",
                       "@extensible\nunion U { a(M) }\nmodel M { id: UUID }",
                       "@extensible\ntypealias T = UUID"] {
            #expect(AnalyzeSupport.analyze(source).codes.contains(.attributeNotAllowedHere), "for: \(source)")
        }
    }

    @Test("@unknownCase, the name in the design document, points at the real one")
    func oldNameIsRedirected() {
        let result = AnalyzeSupport.analyze("@unknownCase\nenum S { a }")
        #expect(result.codes == [.unknownAttribute])
        #expect(result.helps.contains { $0.contains("@extensible") })
    }
}
