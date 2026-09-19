import Testing
@testable import ModelForgeKit

@Suite("Parser")
struct ParserTests {

    @Test("parses the end-to-end example from the proposal")
    func parsesEndToEndExample() {
        let result = ParseSupport.parse("""
        /// A user account in the application.
        model User {
            /// Stable account identifier.
            @json("user_id")
            id: UUID

            name: String
            email: String?

            status: UserStatus = .active

            @transient
            isSelected: Bool = false
        }

        enum UserStatus {
            active
            suspended
            deleted
        }

        @discriminator("type")
        union UserAction {
            renamed(RenameAction)
            deleted(DeleteAction)
        }

        typealias UserID = UUID
        """)

        #expect(result.diagnostics.isEmpty)
        #expect(result.declarationNames == ["User", "UserStatus", "UserAction", "UserID"])

        let user = ParseSupport.model(result, named: "User")
        #expect(user?.documentation.map(\.text) == ["A user account in the application."])
        #expect(user?.fields.map(\.name.text) == ["id", "name", "email", "status", "isSelected"])
        #expect(user?.fields.first?.attributes.first?.name.text == "json")
    }

    @Test("parses every container type, including nested ones")
    func parsesContainerTypes() {
        let result = ParseSupport.parse("""
        model Container {
            users: [User]
            tags: Set<String>
            metadata: Map<String, String>
            groups: [[User]]
            usersByID: Map<UUID, User>
            optionalUsers: [User?]
            maybe: String?
        }
        """)
        #expect(result.diagnostics.isEmpty)
        let described = ParseSupport.model(result, named: "Container")?
            .fields.map { SyntaxDumper.describe($0.type) }
        #expect(described == ["[User]", "Set<String>", "Map<String, String>",
                              "[[User]]", "Map<UUID, User>", "[User?]", "String?"])
    }

    @Test("Set and Map are contextual, so they stay usable as field names")
    func setAndMapAreContextual() {
        let result = ParseSupport.parse("""
        model Options {
            set: Bool
            map: String
        }
        """)
        #expect(result.diagnostics.isEmpty)
        #expect(ParseSupport.model(result, named: "Options")?.fields.map(\.name.text) == ["set", "map"])
    }

    @Test("parses every literal form a default can take")
    func parsesDefaults() {
        let result = ParseSupport.parse("""
        model Project {
            name: String = "untitled"
            archived: Bool = false
            retryCount: Int32 = 0
            offset: Int32 = -1
            ratio: Double = 1.5
            tags: [String] = []
            metadata: Map<String, String> = {}
            status: Status = .active
            note: String? = null
        }
        """)
        #expect(result.diagnostics.isEmpty)
        let defaults = ParseSupport.model(result, named: "Project")?
            .fields.compactMap { $0.defaultValue.map(SyntaxDumper.describe) }
        #expect(defaults == ["\"untitled\"", "false", "0", "-1", "1.5", "[]", "{}", ".active", "null"])
    }

    @Test("parses attribute argument forms")
    func parsesAttributeArguments() {
        let result = ParseSupport.parse("""
        @serializable
        @discriminator("kind")
        model A {
            @deprecated("Use b instead")
            @json("a_id")
            a: String
        }
        """)
        #expect(result.diagnostics.isEmpty)
        let model = ParseSupport.model(result, named: "A")
        #expect(model?.attributes.map(\.name.text) == ["serializable", "discriminator"])
        #expect(model?.fields.first?.attributes.map(\.name.text) == ["deprecated", "json"])
    }

    @Test("produces a readable dump")
    func producesReadableDump() {
        let result = ParseSupport.parse("""
        model User {
            id: UUID
            tags: [String] = []
        }
        """)
        #expect(result.dump == """
        document
          model User  @1:1
            field id: UUID  @2:5
            field tags: [String] = []  @3:5
        """)
    }
}
