import Testing
@testable import ModelForgeKit

@Suite("IR")
struct IRTests {

    @Test("spelling differences normalize to the same IR")
    func spellingNormalizes() {
        let spaced = AnalyzeSupport.analyze("""
        model A {
            x  :  [ User ? ]
            y: Map < String , User >
        }
        model User { id: UUID }
        """)
        let tight = AnalyzeSupport.analyze("""
        model A {
            x:[User?]
            y:Map<String,User>
        }
        model User { id: UUID }
        """)
        #expect(spaced.dump == tight.dump)
        #expect(spaced.diagnostics.isEmpty)
    }

    @Test("attributes become typed fields rather than staying syntax")
    func attributesBecomeTypedFields() {
        let result = AnalyzeSupport.analyze("""
        model A {
            @json("a_id")
            @deprecated("gone soon")
            id: UUID
            @transient
            selected: Bool = false
        }
        """)
        let fields = result.model("A")?.fields
        #expect(fields?[0].serializedName == "a_id")
        #expect(fields?[0].deprecation?.message == "gone soon")
        #expect(fields?[1].isTransient == true)
        #expect(fields?[1].wireName == "selected")
    }

    @Test("the dump is stable and readable")
    func dumpIsReadable() {
        let result = AnalyzeSupport.analyze("""
        /// A user.
        model User {
            @json("user_id")
            id: UUID
            tags: [String] = []
        }
        """)
        #expect(result.dump == """
        module
          model User
            doc "A user."
            field id: UUID json="user_id"
            field tags: [String] = [] transient
        """.replacingOccurrences(of: " transient", with: ""))
    }

    @Test("scalars are distinguishable from declared types without a lookup")
    func scalarsAreDistinct() {
        let result = AnalyzeSupport.analyze("""
        model A { a: String\n b: Other }
        model Other { c: Bool }
        """)
        #expect(result.model("A")?.fields[0].type == .scalar(.string))
        #expect(result.model("A")?.fields[1].type == .named("Other", .model))
    }

    @Test("every declaration records where its name is, not just where it starts")
    func declarationsCarryNameRanges() {
        let result = AnalyzeSupport.analyze("""
        model User { id: UUID }
        enum Status { active }
        union Action { renamed(User) }
        typealias ID = UUID
        """)

        for type in result.module.types {
            guard let origin = type.origin, let name = type.nameOrigin else {
                Issue.record("\(type.name) is missing a source range")
                continue
            }
            // The name sits inside the declaration but is not the whole of it — which is
            // what lets the sidebar's jump select the name rather than flooding the editor.
            #expect(name.start >= origin.start)
            #expect(name.end <= origin.end)
            #expect(name.utf16Range.count == type.name.count)
        }
    }
}
