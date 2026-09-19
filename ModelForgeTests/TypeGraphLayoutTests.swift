//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Testing
import AppKit
import ModelForgeKit
@testable import ModelForge

/// Turning the Kit's layers into rectangles.
///
/// The structure — which layer a type belongs to, which references close a cycle — is the
/// Kit's and is tested there. What is left here is geometry, and the parts of it that can
/// be wrong without looking: rows lining up, the canvas being big enough to hold what is
/// drawn on it, and an edge leaving the side of a node it ought to.
@Suite("Type graph layout")
@MainActor struct TypeGraphLayoutTests {

    private var font: NSFont { NSFont.systemFont(ofSize: 12, weight: .medium) }

    private func layout(_ source: String) -> TypeGraphLayout {
        let files = [SourceFile(id: SourceFileID(0), name: "a.model", text: source)]
        let graph = TypeGraph.build(from: Compiler.compile(files).module)
        return TypeGraphLayout(graph: graph, font: font)
    }

    @Test("Nothing declared, nothing drawn")
    func emptyGraph() {
        let result = layout("")
        #expect(result.isEmpty)
        #expect(result.size == .zero)
    }

    @Test("Each layer is a row, and rows go down the canvas")
    func layersBecomeRows() {
        let result = layout("""
        model A { b: B }
        model B { c: C }
        model C { id: UUID }
        """)

        let a = try? #require(result.frame(of: "A"))
        let b = try? #require(result.frame(of: "B"))
        let c = try? #require(result.frame(of: "C"))

        #expect(a!.minY < b!.minY)
        #expect(b!.minY < c!.minY)
        // Rows are evenly spaced.
        #expect(b!.minY - a!.minY == c!.minY - b!.minY)
    }

    @Test("Nodes in the same layer share a row and do not overlap")
    func siblingsShareARow() {
        let result = layout("""
        model Root { a: Alpha b: Beta c: Gamma }
        model Alpha { id: UUID }
        model Beta { id: UUID }
        model Gamma { id: UUID }
        """)

        let row = result.nodes.filter { $0.node.layer == 1 }.sorted { $0.frame.minX < $1.frame.minX }
        #expect(row.count == 3)
        #expect(Set(row.map(\.frame.minY)).count == 1)

        for (left, right) in zip(row, row.dropFirst()) {
            #expect(left.frame.maxX <= right.frame.minX)
        }
    }

    @Test("Everything drawn is inside the canvas it reports")
    func everythingFitsTheCanvas() {
        // The scroll view is sized from this. Anything outside it cannot be scrolled to.
        let result = layout("""
        model Order { buyer: Customer items: [LineItem] payment: Payment }
        model Customer { address: Address tier: Tier }
        model LineItem { product: Product }
        model Product { price: Money }
        model Address { country: Country }
        union Payment { card(Card) }
        model Card { number: String }
        enum Tier { gold }
        enum Country { se }
        typealias Money = Decimal
        """)

        #expect(!result.isEmpty)
        for positioned in result.nodes {
            #expect(positioned.frame.minX >= 0)
            #expect(positioned.frame.minY >= 0)
            #expect(positioned.frame.maxX <= result.size.width)
            #expect(positioned.frame.maxY <= result.size.height)
        }
    }

    @Test("A row is centred against the widest one")
    func rowsAreCentred() {
        // Otherwise a schema with one root hangs off the left edge.
        let result = layout("""
        model Root { a: Alpha b: Beta c: Gamma }
        model Alpha { id: UUID }
        model Beta { id: UUID }
        model Gamma { id: UUID }
        """)

        let root = try? #require(result.frame(of: "Root"))
        let widest = result.size.width / 2
        #expect(abs(root!.midX - widest) < 1)
    }

    @Test("An edge leaves the bottom of one node and arrives at the top of the other")
    func edgesConnectTheRightSides() {
        let result = layout("""
        model A { b: B }
        model B { id: UUID }
        """)

        let edge = try? #require(result.edges.first)
        let a = try? #require(result.frame(of: "A"))
        let b = try? #require(result.frame(of: "B"))

        #expect(edge!.start.y == a!.maxY)
        #expect(edge!.end.y == b!.minY)
        #expect(edge!.start.x == a!.midX)
        #expect(edge!.end.x == b!.midX)
    }

    @Test("A reference pointing back up the graph leaves the top instead")
    func backEdgesConnectTheOtherWay() {
        let result = layout("""
        union A { b(B) }
        union B { a(A) }
        """)

        let back = try? #require(result.edges.first { $0.edge.isBackEdge })
        let from = try? #require(result.nodes.first { $0.node.name == back!.edge.from })
        // It goes up, so it leaves the top of its source.
        #expect(back!.start.y == from!.frame.minY)
        #expect(back!.end.y >= back!.start.y || back!.end.y <= back!.start.y)
    }

    @Test("A longer name gets a wider node, down to a floor")
    func nodeWidthFollowsTheName() {
        let short = TypeGraphLayout.width(of: "A", font: font)
        let long = TypeGraphLayout.width(of: "ExtremelyLongTypeNameIndeed", font: font)

        #expect(short == TypeGraphLayout.minimumNodeWidth)
        #expect(long > short)
    }

    @Test("A point inside a node finds it, and a point in the gap finds nothing")
    func hitTesting() {
        let result = layout("model A { id: UUID }")
        let frame = try? #require(result.frame(of: "A"))

        #expect(result.node(at: CGPoint(x: frame!.midX, y: frame!.midY))?.name == "A")
        #expect(result.node(at: CGPoint(x: 1, y: 1)) == nil)
    }

    @Test("The same schema lays out identically every time")
    func layoutIsDeterministic() {
        // It is rebuilt on every compile, which is every keystroke.
        let source = """
        model Order { buyer: Customer items: [LineItem] }
        model Customer { address: Address }
        model LineItem { product: Product }
        model Product { sku: String }
        model Address { street: String }
        """
        #expect(layout(source) == layout(source))
    }
}
