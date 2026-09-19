import Testing
@testable import ModelForgeKit

@Suite("Type graph")
struct TypeGraphTests {

    private func graph(_ source: String) -> TypeGraph {
        TypeGraph.build(from: AnalyzeSupport.analyze(source).module)
    }

    private func edge(_ graph: TypeGraph, from: String, to: String) -> TypeGraph.Edge? {
        graph.edges.first { $0.from == from && $0.to == to }
    }

    // MARK: What becomes a node and an edge

    @Test("Every declared type is a node, whatever kind it is")
    func everyTypeIsANode() {
        let result = graph("""
        model User { id: UUID }
        enum Status { active }
        union Payment { card(Card) }
        model Card { number: String }
        typealias UserID = UUID
        """)

        #expect(Set(result.nodes.map(\.name)) == ["User", "Status", "Payment", "Card", "UserID"])
        #expect(result["Status"]?.kind == .enum)
        #expect(result["Payment"]?.kind == .union)
        #expect(result["UserID"]?.kind == .alias)
    }

    @Test("A field pointing at another type is an edge, labelled with the field")
    func fieldsMakeEdges() {
        let result = graph("""
        model Account { owner: User }
        model User { id: UUID }
        """)

        #expect(result.edges.count == 1)
        #expect(edge(result, from: "Account", to: "User")?.label == "owner")
    }

    @Test("A reference inside a collection still counts")
    func referencesInsideCollections() {
        let result = graph("""
        model Team { members: [User] lookup: Map<String, Role> tags: Set<Label> }
        model User { id: UUID }
        model Role { name: String }
        model Label { name: String }
        """)

        #expect(edge(result, from: "Team", to: "User") != nil)
        #expect(edge(result, from: "Team", to: "Role") != nil)
        #expect(edge(result, from: "Team", to: "Label") != nil)
    }

    @Test("A union's payloads and an alias's target are edges too")
    func unionsAndAliases() {
        let result = graph("""
        union Payment { card(Card) cash(Cash) }
        model Card { number: String }
        model Cash { amount: Decimal }
        typealias Money = Decimal
        model Order { method: Payment }
        """)

        #expect(edge(result, from: "Payment", to: "Card")?.label == "card")
        #expect(edge(result, from: "Payment", to: "Cash")?.label == "cash")
        #expect(edge(result, from: "Order", to: "Payment") != nil)
    }

    @Test("Scalars are not nodes, and not edges either")
    func scalarsAreLeftOut() {
        // Every model has a String in it somewhere. A node everything points at says
        // nothing about the shape of the schema.
        let result = graph("model User { id: UUID name: String age: Int32 }")

        #expect(result.nodes.map(\.name) == ["User"])
        #expect(result.edges.isEmpty)
    }

    @Test("A name that does not resolve is not drawn")
    func unresolvedNamesAreLeftOut() {
        let result = graph("model A { owner: NoSuchType }")

        #expect(result.nodes.map(\.name) == ["A"])
        #expect(result.edges.isEmpty)
    }

    @Test("Three fields of the same type draw one line, not three")
    func duplicateReferencesCollapse() {
        let result = graph("""
        model Order { buyer: User seller: User approver: User }
        model User { id: UUID }
        """)

        #expect(result.edges.count == 1)
        // The first field named is the one that explains the line.
        #expect(edge(result, from: "Order", to: "User")?.label == "buyer")
    }

    @Test("A type referring to itself does not get a loop drawn on it")
    func selfReferences() {
        let result = graph("""
        union Tree { leaf(Leaf) branch(Tree) }
        model Leaf { value: String }
        """)

        #expect(result.edges.allSatisfy { $0.from != $0.to })
        #expect(edge(result, from: "Tree", to: "Leaf") != nil)
    }

    // MARK: Layering

    @Test("A chain of references becomes a chain of layers")
    func aChainLayers() {
        let result = graph("""
        model A { b: B }
        model B { c: C }
        model C { id: UUID }
        """)

        #expect(result["A"]?.layer == 0)
        #expect(result["B"]?.layer == 1)
        #expect(result["C"]?.layer == 2)
        #expect(result.layerCount == 3)
    }

    @Test("A type sits below everything that refers to it, by the longest path")
    func theLongestPathWins() {
        // D is reachable from A directly and through B and C. It belongs under both.
        let result = graph("""
        model A { b: B c: C d: D }
        model B { d: D }
        model C { d: D }
        model D { id: UUID }
        """)

        #expect(result["A"]?.layer == 0)
        #expect(result["B"]?.layer == 1)
        #expect(result["C"]?.layer == 1)
        #expect(result["D"]?.layer == 2)
    }

    @Test("Types nothing refers to all start at the top")
    func rootsShareTheTopLayer() {
        let result = graph("""
        model A { shared: Shared }
        model B { shared: Shared }
        model Shared { id: UUID }
        """)

        #expect(result["A"]?.layer == 0)
        #expect(result["B"]?.layer == 0)
        #expect(result["Shared"]?.layer == 1)
    }

    @Test("A standalone type is its own layer-zero island")
    func islands() {
        let result = graph("""
        model A { id: UUID }
        enum Status { active }
        """)

        #expect(result["A"]?.layer == 0)
        #expect(result["Status"]?.layer == 0)
        #expect(result.edges.isEmpty)
    }

    // MARK: Cycles

    @Test("A cycle is broken rather than layered forever")
    func aCycleTerminates() {
        // Mutually recursive unions are legal and the Swift emitter makes them indirect.
        // Layering one without breaking it would not terminate.
        let result = graph("""
        union A { b(B) }
        union B { a(A) }
        """)

        #expect(result.nodes.count == 2)
        #expect(result.edges.count == 2)
        #expect(result.edges.count { $0.isBackEdge } == 1)
        #expect(result.nodes.allSatisfy { $0.layer >= 0 })
    }

    @Test("A longer cycle is broken exactly once")
    func aLongerCycle() {
        let result = graph("""
        union A { b(B) }
        union B { c(C) }
        union C { a(A) }
        """)

        #expect(result.edges.count { $0.isBackEdge } == 1)
        #expect(result.layerCount == 3)
    }

    @Test("Breaking a cycle does not strand the types in it")
    func everyNodeGetsALayer() {
        let result = graph("""
        model Root { a: A }
        union A { b(B) }
        union B { a(A) }
        """)

        #expect(result.nodes.count == 3)
        #expect(result.nodes.allSatisfy { $0.layer >= 0 })
        #expect(result["Root"]?.layer == 0)
    }

    // MARK: Determinism

    @Test("The same schema always draws the same way")
    func layoutIsDeterministic() {
        // The graph is rebuilt on every compile, which is every keystroke. A layout that
        // shuffled would make the canvas unreadable while you type.
        let source = """
        model Order { buyer: User items: [Item] payment: Payment }
        model User { id: UUID address: Address }
        model Item { sku: String }
        model Address { street: String }
        union Payment { card(Card) }
        model Card { number: String }
        """
        let first = graph(source)
        let second = graph(source)

        #expect(first == second)
        #expect(first.nodes.map { "\($0.name):\($0.layer):\($0.order)" }
                == second.nodes.map { "\($0.name):\($0.layer):\($0.order)" })
    }

    @Test("Within a layer, every node has its own place")
    func ordersAreUniqueWithinALayer() {
        let result = graph("""
        model Root { a: A b: B c: C }
        model A { id: UUID }
        model B { id: UUID }
        model C { id: UUID }
        """)

        let second = result.nodes(inLayer: 1)
        #expect(second.count == 3)
        #expect(Set(second.map(\.order)).count == 3)
        #expect(second.map(\.order) == [0, 1, 2])
    }

    @Test("An empty project is an empty graph")
    func emptyProject() {
        let result = graph("")
        #expect(result.isEmpty)
        #expect(result.layerCount == 0)
    }

    @Test("A node knows where it is declared, so clicking it can go there")
    func nodesCarryTheirOrigin() {
        let result = graph("model User { id: UUID }")
        #expect(result["User"]?.origin != nil)
        #expect(result["User"]?.origin?.start.line == 1)
    }
}

@Suite("Type graph focused on a file")
struct TypeGraphFocusTests {

    /// Two files: `user.model` declares User and Address, `order.model` the rest.
    private func twoFileGraph() -> (TypeGraph, user: SourceFileID, order: SourceFileID) {
        let files = [
            SourceFile(id: SourceFileID(0), name: "user.model", text: """
            model User {
                id: UUID
                address: Address
            }
            model Address { street: String }
            """),
            SourceFile(id: SourceFileID(1), name: "order.model", text: """
            model Order {
                buyer: User
                payment: Payment
            }
            union Payment { card(Card) }
            model Card { number: String }
            model Unrelated { note: String }
            """)
        ]
        return (TypeGraph.build(from: Compiler.compile(files).module),
                SourceFileID(0), SourceFileID(1))
    }

    @Test("A file's own types are all there")
    func ownTypesAreKept() {
        let (graph, user, _) = twoFileGraph()
        let focused = graph.focused(on: user)

        #expect(focused["User"] != nil)
        #expect(focused["Address"] != nil)
    }

    @Test("Types directly connected from other files come along as context")
    func neighboursComeAlong() {
        // A file shown in isolation has nothing left to reference, which is the opposite
        // of the point of a reference graph.
        let (graph, user, order) = twoFileGraph()
        let focused = graph.focused(on: user)

        #expect(focused["Order"] != nil)
        #expect(focused["Order"]?.sourceFile == order)
    }

    @Test("Types with no connection to the file are left out")
    func distantTypesAreDropped() {
        let (graph, user, _) = twoFileGraph()
        let focused = graph.focused(on: user)

        // Payment and Card reach User only through Order, which is two hops.
        #expect(focused["Payment"] == nil)
        #expect(focused["Card"] == nil)
        #expect(focused["Unrelated"] == nil)
    }

    @Test("A line between two pieces of context is not drawn")
    func edgesBetweenNeighboursAreDropped() {
        // It says nothing about the file being looked at.
        let (graph, _, order) = twoFileGraph()
        let focused = graph.focused(on: order)
        let own = Set(focused.nodes.filter { $0.sourceFile == order }.map(\.name))

        #expect(focused.edges.allSatisfy { own.contains($0.from) || own.contains($0.to) })
    }

    @Test("Every edge kept has both ends still in the picture")
    func edgesAreWellFormed() {
        let (graph, user, _) = twoFileGraph()
        let focused = graph.focused(on: user)
        let present = Set(focused.nodes.map(\.name))

        #expect(focused.edges.allSatisfy { present.contains($0.from) && present.contains($0.to) })
    }

    @Test("The subset is laid out again, not left with the whole graph's layers")
    func theSubsetIsRelayered() {
        // Otherwise a focused view starts at layer 3 with nothing above it.
        let (graph, user, _) = twoFileGraph()
        let focused = graph.focused(on: user)

        #expect(focused.nodes.map(\.layer).min() == 0)
        #expect(Set(focused.nodes(inLayer: 0).map(\.order)).count
                == focused.nodes(inLayer: 0).count)
    }

    @Test("A file that declares nothing focuses to nothing")
    func anEmptyFile() {
        let (graph, _, _) = twoFileGraph()
        #expect(graph.focused(on: SourceFileID(99)).isEmpty)
    }

    @Test("Focusing is deterministic too")
    func focusIsDeterministic() {
        let (graph, user, _) = twoFileGraph()
        #expect(graph.focused(on: user) == graph.focused(on: user))
    }
}
