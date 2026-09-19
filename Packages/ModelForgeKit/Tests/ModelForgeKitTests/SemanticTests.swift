import Testing
@testable import ModelForgeKit

@Suite("Semantic analysis")
struct SemanticTests {

    // MARK: Namespace

    @Test("files in a project share one flat namespace, with no imports")
    func flatNamespaceAcrossFiles() {
        let result = AnalyzeSupport.analyze([
            (name: "user.model", text: """
            model User {
                id: UUID
                address: Address
                status: Status
            }
            """),
            (name: "common.model", text: """
            model Address {
                street: String
            }

            enum Status {
                active
            }
            """)
        ])
        #expect(result.diagnostics.isEmpty)
        #expect(result.model("User")?.fields.map { $0.type.described } == ["UUID", "Address", "Status"])
    }

    @Test("a duplicate declaration across files points at the first one")
    func duplicateAcrossFiles() {
        let result = AnalyzeSupport.analyze([
            (name: "a.model", text: "model User { id: UUID }"),
            (name: "b.model", text: "model User { name: String }")
        ])
        #expect(result.codes == [.duplicateDeclaration])
        #expect(result.diagnostics.first?.range.file == SourceFileID(1))
        #expect(result.diagnostics.first?.notes.first?.range?.file == SourceFileID(0))
        // Only the first survives, so the generated code never declares the type twice.
        #expect(result.module.types.count == 1)
    }

    @Test("each type remembers which file declared it")
    func typesRememberTheirFile() {
        let result = AnalyzeSupport.analyze([
            (name: "a.model", text: "model A { id: UUID }"),
            (name: "b.model", text: "model B { id: UUID }")
        ])
        #expect(result.module.types(in: SourceFileID(0)).map(\.name) == ["A"])
        #expect(result.module.types(in: SourceFileID(1)).map(\.name) == ["B"])
    }

    // MARK: Types

    @Test("an unknown type is reported with a spelling suggestion")
    func unknownTypeSuggests() {
        let result = AnalyzeSupport.analyze("""
        model User { id: UUID }
        model Team { manager: Usre? }
        """)
        #expect(result.codes == [.unknownType])
        #expect(result.messages == ["unknown type 'Usre'"])
        #expect(result.helps == ["did you mean 'User'?"])
        // It still flows through to the emitters so the previews keep rendering.
        #expect(result.model("Team")?.fields.first?.type == .optional(.unresolved("Usre")))
    }

    @Test("Int is rejected outright, with fix-its for both widths")
    func intIsRejected() {
        let result = AnalyzeSupport.analyze("model A { count: Int }")
        #expect(result.codes == [.ambiguousIntWidth])
        #expect(result.diagnostics.first?.fixIts.map(\.replacement) == ["Int64", "Int32"])
    }

    @Test("declaring a built-in name is an error")
    func builtinRedeclared() {
        let result = AnalyzeSupport.analyze("model String { a: Bool }")
        #expect(result.codes == [.builtinRedeclared])
    }

    @Test("a bare container needs type arguments")
    func bareContainer() {
        let result = AnalyzeSupport.analyze("model A { tags: Set }")
        #expect(result.codes == [.genericArity])
    }

    @Test("nested containers normalize the same however they are spelled")
    func nestedContainersNormalize() {
        let a = AnalyzeSupport.analyze("model A { x: [User?] }\nmodel User { id: UUID }")
        let b = AnalyzeSupport.analyze("model A { x:[ User ? ] }\nmodel User { id: UUID }")
        #expect(a.dump == b.dump)
        #expect(a.model("A")?.fields.first?.type == .list(.optional(.named("User", .model))))
    }

    // MARK: Members

    @Test("a duplicate field is reported once and dropped")
    func duplicateField() {
        let result = AnalyzeSupport.analyze("model A { id: UUID\n id: String }")
        #expect(result.codes == [.duplicateField])
        #expect(result.model("A")?.fields.count == 1)
    }

    @Test("two fields cannot serialize to the same name")
    func duplicateSerializedName() {
        let result = AnalyzeSupport.analyze("""
        model A {
            @json("id")
            identifier: UUID
            id: String
        }
        """)
        #expect(result.codes == [.duplicateSerializedName])
    }

    @Test("a keyword member name is only a warning, because the emitters escape it")
    func reservedMemberName() {
        let result = AnalyzeSupport.analyze("model A { `class`: String }".replacingOccurrences(of: "`", with: ""))
        #expect(result.codes == [.reservedName])
        #expect(result.errors.isEmpty)
        #expect(result.model("A")?.fields.map(\.name) == ["class"])
    }

    // MARK: Defaults

    @Test("accepts every valid default form")
    func validDefaults() {
        let result = AnalyzeSupport.analyze("""
        enum Status { active }
        model Project {
            name: String = "untitled"
            archived: Bool = false
            retries: Int32 = 0
            ratio: Double = 1.5
            whole: Double = 2
            tags: [String] = []
            unique: Set<String> = []
            metadata: Map<String, String> = {}
            status: Status = .active
            note: String? = null
        }
        """)
        #expect(result.diagnostics.isEmpty)
        #expect(result.model("Project")?.fields.compactMap { $0.defaultValue?.described }
                == ["\"untitled\"", "false", "0", "1.5", "2", "[]", "[]", "{}", ".active", "null"])
    }

    @Test("rejects a default of the wrong type")
    func mismatchedDefault() {
        let result = AnalyzeSupport.analyze("""
        model A {
            name: String = 3
            flag: Bool = "yes"
        }
        """)
        #expect(result.codes == [.invalidDefaultValue, .invalidDefaultValue])
        #expect(result.model("A")?.fields.allSatisfy { $0.defaultValue == nil } == true)
    }

    @Test("null is only allowed on an optional")
    func nullOnRequiredField() {
        let result = AnalyzeSupport.analyze("model A { name: String = null }")
        #expect(result.codes == [.invalidDefaultValue])
        #expect(result.helps.contains("write 'String?' to allow a null value"))
    }

    @Test("an integer default must fit its declared width")
    func integerRangeChecked() {
        let result = AnalyzeSupport.analyze("model A { small: Int32 = 3000000000 }")
        #expect(result.codes == [.invalidDefaultValue])
        #expect(result.helps.contains("use Int64 for values outside the range of Int32"))
    }

    @Test("an unknown enum case is reported with a suggestion")
    func unknownEnumCase() {
        let result = AnalyzeSupport.analyze("""
        enum Status { active suspended }
        model A { status: Status = .activ }
        """)
        #expect(result.codes == [.unknownEnumCase])
        #expect(result.helps.contains("did you mean '.active'?"))
    }

    @Test("a default follows a type alias")
    func defaultThroughAlias() {
        let result = AnalyzeSupport.analyze("""
        typealias Name = String
        model A { name: Name = "x" }
        """)
        #expect(result.diagnostics.isEmpty)
    }

    // MARK: Attributes

    @Test("a transient field must have a default")
    func transientRequiresDefault() {
        let result = AnalyzeSupport.analyze("""
        model A {
            @transient
            selected: Bool
        }
        """)
        #expect(result.codes == [.transientRequiresDefault])
    }

    @Test("an unknown attribute suggests a correction")
    func unknownAttribute() {
        let result = AnalyzeSupport.analyze("""
        model A {
            @jsn("x")
            id: UUID
        }
        """)
        #expect(result.codes == [.unknownAttribute])
        #expect(result.helps.contains("did you mean '@json'?"))
    }

    @Test("deferred attributes explain themselves instead of saying 'unknown'")
    func deferredAttributeExplained() {
        let result = AnalyzeSupport.analyze("""
        model A {
            @optional
            name: String
        }
        """)
        #expect(result.codes.contains(.unknownAttribute))
        #expect(result.helps.contains { $0.contains("field presence is not supported yet") })
    }

    @Test("an attribute in the wrong place says where it belongs")
    func attributeInWrongPlace() {
        let result = AnalyzeSupport.analyze("""
        @discriminator("t")
        model A { id: UUID }
        """)
        #expect(result.codes == [.attributeNotAllowedHere])
    }

    @Test("@serializable is redundant but harmless")
    func serializableIsRedundant() {
        let result = AnalyzeSupport.analyze("""
        @serializable
        model A { id: UUID }
        """)
        #expect(result.codes == [.redundantAttribute])
        #expect(result.errors.isEmpty)
    }

    // MARK: Unions

    @Test("a union payload must be a model")
    func unionPayloadMustBeAModel() {
        let result = AnalyzeSupport.analyze("""
        enum Kind { a }
        union Bad {
            scalar(Int64)
            listed([Card])
            enumerated(Kind)
        }
        model Card { number: String }
        """)
        #expect(result.codes == [.invalidUnionPayload, .invalidUnionPayload, .invalidUnionPayload])
        // The diagnostic points at the payload, not at the whole union.
        #expect(result.diagnostics.first?.range.start.line == 3)
    }

    @Test("a payload field colliding with the discriminator is rejected")
    func discriminatorClash() {
        let result = AnalyzeSupport.analyze("""
        union Payment {
            card(Card)
        }
        model Card {
            type: String
            number: String
        }
        """)
        #expect(result.codes == [.discriminatorClash])
        #expect(result.helps.contains { $0.contains("@discriminator") })
    }

    @Test("a custom discriminator moves what counts as a collision")
    func customDiscriminator() {
        let result = AnalyzeSupport.analyze("""
        @discriminator("kind")
        union Payment {
            card(Card)
        }
        model Card {
            type: String
            number: String
        }
        """)
        #expect(result.diagnostics.isEmpty)
        #expect(result.union("Payment")?.discriminator == "kind")
    }

    // MARK: Recursion

    @Test("a model that contains itself is an error")
    func selfContainingModel() {
        let result = AnalyzeSupport.analyze("model Node { parent: Node? }")
        #expect(result.codes == [.recursiveModel])
    }

    @Test("a mutually recursive pair of models is an error")
    func mutuallyRecursiveModels() {
        let result = AnalyzeSupport.analyze("""
        model A { b: B }
        model B { a: A }
        """)
        #expect(result.codes == [.recursiveModel, .recursiveModel])
    }

    @Test("recursion through a collection is fine")
    func recursionThroughCollection() {
        let result = AnalyzeSupport.analyze("""
        model Node {
            children: [Node]
            tagged: Map<String, Node>
        }
        """)
        #expect(result.diagnostics.isEmpty)
    }

    @Test("a cycle through a union is allowed and marks the union indirect")
    func recursionThroughUnion() {
        let result = AnalyzeSupport.analyze("""
        union Expr {
            negated(Negation)
        }
        model Negation { inner: Expr }
        """)
        #expect(result.errors.isEmpty)
        #expect(result.union("Expr")?.isRecursive == true)
    }

    @Test("a malformed attribute argument does not cascade into a missing-paren error")
    func malformedAttributeArgumentDoesNotCascade() {
        // `optional` is a bare identifier, which is not a valid argument. Exactly two
        // things are worth saying: that the argument is not a value, and that '@presence'
        // is deferred anyway. A third complaint about the missing ')' would be noise.
        let result = AnalyzeSupport.analyze("""
        model A {
            @presence(optional)
            name: String
        }
        """)
        #expect(result.codes == [.unknownAttribute, .expectedLiteral])
        #expect(result.helps.contains { $0.contains("field presence is not supported yet") })
    }
}
