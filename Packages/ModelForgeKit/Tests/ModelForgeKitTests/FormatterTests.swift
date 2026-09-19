import Testing
import Foundation
@testable import ModelForgeKit

/// One canonical layout, so a schema shared by two app teams never shows a diff because
/// somebody's editor indents differently.
///
/// The two properties that matter more than any particular spacing rule: formatting must
/// not change what the file *means*, and it must not lose anything the author wrote.
@Suite("Formatter")
struct FormatterTests {

    private func format(_ text: String) throws -> String {
        try SourceFormatter.format(SourceFile(id: SourceFileID(0), name: "t.model", text: text))
    }

    // MARK: The properties that matter

    @Test("formatting never changes what the file means")
    func preservesMeaning() throws {
        let messy = """
        @identifiable
        model User{
            @json("user_id")
            id:UUID
            name   :   String
            tags:[String]=[]
            m: Map<String,User>
            s: Set<User?>
        }
        @extensible enum Status { active  suspended }
        @discriminator("kind") union Act { a(User) }
        typealias   ID=UUID
        """
        let before = AnalyzeSupport.analyze(messy)
        let after = AnalyzeSupport.analyze(try format(messy))
        #expect(before.dump == after.dump)
        #expect(after.diagnostics.isEmpty)
    }

    @Test("formatting twice changes nothing the second time")
    func isIdempotent() throws {
        let once = try format("""
        // note
        model A{ id:UUID
          name:String }
        enum B { x  y }
        """)
        #expect(try format(once) == once)
    }

    @Test("already-canonical sources come back untouched")
    func leavesCanonicalSourcesAlone() throws {
        // The starter document and every fixture are written by hand, so this doubles as a
        // check that they are in the style the tool itself would produce.
        let starter = SourceFile(id: SourceFileID(0),
                                 name: StarterDocument.fileName,
                                 text: StarterDocument.source)
        #expect(SourceFormatter.isFormatted(starter))

        for project in ["EndToEnd", "AllScalars"] {
            for file in Snapshot.project(project) {
                #expect(SourceFormatter.isFormatted(file), "\(project)/\(file.name) is not canonical")
            }
        }
    }

    @Test("every comment survives")
    func keepsEveryComment() throws {
        let source = """
        // file note

        /// doc on the model
        model A {
            // why this field exists
            id: UUID  // trailing note
            /// doc on a field
            name: String
        }
        // note before the enum
        enum B { x }
        """
        let output = try format(source)
        for fragment in ["// file note", "/// doc on the model", "// why this field exists",
                         "// trailing note", "/// doc on a field", "// note before the enum"] {
            #expect(output.contains(fragment), "lost \(fragment)")
        }
    }

    // MARK: Layout

    @Test("expands one-liners and normalizes spacing")
    func normalizesLayout() throws {
        #expect(try format("model A{id:UUID}") == """
        model A {
            id: UUID
        }

        """)
    }

    @Test("collapses runs of blank lines between members to one")
    func collapsesBlankLines() throws {
        let output = try format("""
        model A {
            a: String



            b: String
        }
        """)
        #expect(output == """
        model A {
            a: String

            b: String
        }

        """)
    }

    @Test("separates declarations with exactly one blank line")
    func separatesDeclarations() throws {
        let output = try format("model A { a: String }\n\n\n\nmodel B { b: String }")
        #expect(output.contains("}\n\nmodel B"))
    }

    @Test("containers and attributes take their canonical spelling")
    func normalizesTypesAndAttributes() throws {
        let output = try format("""
        model A {
            @json( "a_id" )
            a: Map<String,[B?]>
        }
        model B { id: UUID }
        """)
        #expect(output.contains("@json(\"a_id\")"))
        #expect(output.contains("a: Map<String, [B?]>"))
    }

    @Test("an empty declaration keeps its braces")
    func emptyDeclaration() throws {
        #expect(try format("model A {}").contains("model A {\n}"))
    }

    // MARK: Refusing

    @Test("refuses to format a file that does not parse")
    func refusesBrokenSource() {
        // Rewriting source from a guess at what the author meant is how a formatter
        // destroys work.
        #expect(throws: SourceFormatter.Failure.doesNotParse) {
            try format("model A { id: UUID")
        }
        #expect(throws: SourceFormatter.Failure.doesNotParse) {
            try format("this is not a schema")
        }
    }

    @Test("a semantic error does not stop formatting, because layout does not depend on it")
    func formatsDespiteSemanticErrors() throws {
        let output = try format("model A{ x:Nonexistent }")
        #expect(output.contains("x: Nonexistent"))
    }
}
