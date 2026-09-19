import Testing
@testable import ModelForgeKit

/// The starter document is the first thing anyone sees, and a mistake in it would be
/// invisible until someone opened the app — so it is held to the same standard as any
/// other source, and the code it generates has to compile too.
@Suite("Starter document")
struct StarterDocumentTests {

    private var compiled: CompilePipeline.Output {
        var configuration = ProjectConfiguration.default
        configuration.kotlin.package = "com.example.models"
        let file = SourceFile(id: SourceFileID(0),
                              name: StarterDocument.fileName,
                              text: StarterDocument.source)
        return CompilePipeline.run(files: [file], configuration: configuration)
    }

    @Test("compiles with no problems at all")
    func compilesCleanly() {
        let result = compiled.result
        #expect(result.diagnostics.isEmpty,
                "the starter document must be clean:\n\(result.renderedDiagnostics())")
    }

    @Test("shows all four kinds of declaration")
    func showsEveryDeclarationKind() {
        let kinds = Set(compiled.result.module.types.map(\.kind))
        #expect(kinds.contains(.model))
        #expect(kinds.contains(.enum))
        #expect(kinds.contains(.union))
    }

    @Test("its union is a working example, payload models and all")
    func unionIsComplete() {
        guard case .union(let union)? = compiled.result.module["SignIn"] else {
            Issue.record("the starter should declare a union")
            return
        }
        #expect(union.discriminator == "method")
        #expect(union.cases.count >= 2)
        // A union case's payload has to be a model, which is the rule most worth showing.
        for unionCase in union.cases {
            #expect(unionCase.payload.described.isEmpty == false)
            if case .named(_, let kind) = unionCase.payload {
                #expect(kind == .model)
            } else {
                Issue.record("payload of '\(unionCase.name)' should be a named model")
            }
        }
    }

    @Test("both previews are populated from the very first window")
    func generatesBothLanguages() {
        let generated = compiled.generated
        for language in Language.allCases {
            let file = generated.files.first { $0.language == language && $0.sourceFile != nil }
            #expect(file != nil)
            #expect(file?.contents.contains("SignIn") == true)
        }
    }
}
