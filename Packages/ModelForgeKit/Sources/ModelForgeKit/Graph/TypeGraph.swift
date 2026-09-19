import Foundation

/// The project's types and the references between them, arranged into layers.
///
/// Structure and arrangement only — no sizes, no coordinates. Where a node actually lands
/// depends on how wide its name renders, which is the app's business; everything that can
/// be got wrong without looking at a screen is here, where it can be tested.
public struct TypeGraph: Sendable, Hashable {

    public struct Node: Sendable, Hashable, Identifiable {
        public let name: String
        public let kind: NamedKind
        public let sourceFile: SourceFileID
        /// Where the name is declared, so clicking the node can go there.
        public let origin: SourceRange?
        /// Distance from a type nothing else refers to. Layer 0 holds the aggregates you
        /// start reading from; their dependencies sit below them.
        public let layer: Int
        /// Position within the layer, left to right.
        public let order: Int

        public var id: String { name }

        public init(name: String, kind: NamedKind, sourceFile: SourceFileID,
                    origin: SourceRange?, layer: Int, order: Int) {
            self.name = name
            self.kind = kind
            self.sourceFile = sourceFile
            self.origin = origin
            self.layer = layer
            self.order = order
        }
    }

    public struct Edge: Sendable, Hashable, Identifiable {
        /// The type that does the referring.
        public let from: String
        /// The type being referred to.
        public let to: String
        /// The field or case that creates the reference.
        public let label: String
        /// Whether this reference points back up the graph — part of a cycle, and left out
        /// of the layering so one can exist at all.
        public let isBackEdge: Bool

        public var id: String { "\(from)→\(to):\(label)" }

        public init(from: String, to: String, label: String, isBackEdge: Bool) {
            self.from = from
            self.to = to
            self.label = label
            self.isBackEdge = isBackEdge
        }
    }

    public let nodes: [Node]
    public let edges: [Edge]

    public init(nodes: [Node], edges: [Edge]) {
        self.nodes = nodes
        self.edges = edges
    }

    public var isEmpty: Bool { nodes.isEmpty }

    /// How many layers deep the graph is.
    public var layerCount: Int {
        (nodes.map(\.layer).max() ?? -1) + 1
    }

    public func nodes(inLayer layer: Int) -> [Node] {
        nodes.filter { $0.layer == layer }.sorted { $0.order < $1.order }
    }

    public subscript(name: String) -> Node? {
        nodes.first { $0.name == name }
    }
}

// MARK: - Building

extension TypeGraph {

    /// Build the graph for a compiled module.
    ///
    /// Only references between types the project declares are drawn. Scalars are left out:
    /// every model has a `String` in it somewhere, and a node everything points at says
    /// nothing about the shape of the schema.
    public static func build(from module: Module) -> TypeGraph {
        let declared = module.typeNames
        var edges: [Edge] = []

        // Declaration order, which is stable across compiles of the same source.
        for type in module.types {
            for (target, label) in references(of: type) where declared.contains(target) {
                // A reference to itself is real — a recursive union — but drawing a loop
                // from a node to itself tells you nothing the `indirect` does not.
                guard target != type.name else { continue }
                edges.append(Edge(from: type.name, to: target, label: label, isBackEdge: false))
            }
        }
        // One edge per pair, keeping the first label, so a model with three fields of the
        // same type does not draw three identical lines.
        edges = deduplicated(edges)

        let backEdges = findBackEdges(in: edges, nodes: module.types.map(\.name))
        edges = edges.map {
            Edge(from: $0.from, to: $0.to, label: $0.label,
                 isBackEdge: backEdges.contains(Pair(from: $0.from, to: $0.to)))
        }

        let layers = layerize(module.types.map(\.name),
                              edges: edges.filter { !$0.isBackEdge })
        let orders = order(module.types.map(\.name), layers: layers, edges: edges)

        let nodes = module.types.map { type in
            Node(name: type.name,
                 kind: type.kind,
                 sourceFile: type.sourceFile,
                 origin: type.nameOrigin ?? type.origin,
                 layer: layers[type.name] ?? 0,
                 order: orders[type.name] ?? 0)
        }
        return TypeGraph(nodes: nodes, edges: edges)
    }

    /// The graph cut down to one file, keeping one hop of context around it.
    ///
    /// Not just the file's own types: a reference graph showing a file in isolation has
    /// nothing left to reference, which is the opposite of the point. Everything directly
    /// connected to one of the file's types comes along, and the caller can tell the two
    /// apart by each node's `sourceFile`.
    ///
    /// The subgraph is laid out again from scratch, so it reads as its own picture rather
    /// than as the big one with pieces missing.
    public func focused(on file: SourceFileID) -> TypeGraph {
        let own = Set(nodes.filter { $0.sourceFile == file }.map(\.name))
        guard !own.isEmpty else { return TypeGraph(nodes: [], edges: []) }

        var kept = own
        for edge in edges {
            if own.contains(edge.from) { kept.insert(edge.to) }
            if own.contains(edge.to) { kept.insert(edge.from) }
        }

        // Only edges with both ends still present, and only those touching the file — a
        // line between two neighbours says nothing about the file being looked at.
        let keptEdges = edges.filter {
            kept.contains($0.from) && kept.contains($0.to)
                && (own.contains($0.from) || own.contains($0.to))
        }

        let names = nodes.filter { kept.contains($0.name) }.map(\.name)
        let layers = TypeGraph.layerize(names, edges: keptEdges.filter { !$0.isBackEdge })
        let orders = TypeGraph.order(names, layers: layers, edges: keptEdges)

        let subset = nodes.filter { kept.contains($0.name) }.map { node in
            Node(name: node.name,
                 kind: node.kind,
                 sourceFile: node.sourceFile,
                 origin: node.origin,
                 layer: layers[node.name] ?? 0,
                 order: orders[node.name] ?? 0)
        }
        return TypeGraph(nodes: subset, edges: keptEdges)
    }

    /// Everything a declaration points at, with the field or case responsible.
    private static func references(of type: TypeDefinition) -> [(String, String)] {
        switch type {
        case .model(let model):
            model.fields.flatMap { field in
                field.type.referencedNames.sorted().map { ($0, field.name) }
            }
        case .union(let union):
            union.cases.flatMap { unionCase in
                unionCase.payload.referencedNames.sorted().map { ($0, unionCase.name) }
            }
        case .alias(let alias):
            alias.target.referencedNames.sorted().map { ($0, alias.name) }
        case .enum:
            []
        }
    }

    private struct Pair: Hashable {
        let from: String
        let to: String
    }

    private static func deduplicated(_ edges: [Edge]) -> [Edge] {
        var seen: Set<Pair> = []
        return edges.filter { seen.insert(Pair(from: $0.from, to: $0.to)).inserted }
    }

    /// Edges that close a cycle, found by depth-first search.
    ///
    /// A schema can legitimately contain one — a recursive union, which the Swift emitter
    /// makes `indirect`. Layering a graph with a cycle in it would not terminate, so these
    /// are set aside for layering and drawn differently.
    private static func findBackEdges(in edges: [Edge], nodes: [String]) -> Set<Pair> {
        var outgoing: [String: [String]] = [:]
        for edge in edges { outgoing[edge.from, default: []].append(edge.to) }

        var back: Set<Pair> = []
        var state: [String: Int] = [:]   // 1 = on the stack, 2 = finished

        // Iterative, so a deep schema cannot overflow the stack.
        for root in nodes.sorted() where state[root] == nil {
            var stack: [(node: String, next: Int)] = [(root, 0)]
            state[root] = 1

            while let top = stack.last {
                let children = outgoing[top.node] ?? []
                if top.next < children.count {
                    stack[stack.count - 1].next += 1
                    let child = children[top.next]
                    switch state[child] {
                    case 1: back.insert(Pair(from: top.node, to: child))
                    case 2: break
                    default:
                        state[child] = 1
                        stack.append((child, 0))
                    }
                } else {
                    state[top.node] = 2
                    stack.removeLast()
                }
            }
        }
        return back
    }

    /// Longest-path layering: a type sits one layer below everything that refers to it.
    fileprivate static func layerize(_ nodes: [String], edges: [Edge]) -> [String: Int] {
        var incoming: [String: [String]] = [:]
        var outgoing: [String: [String]] = [:]
        for edge in edges {
            incoming[edge.to, default: []].append(edge.from)
            outgoing[edge.from, default: []].append(edge.to)
        }

        var layer: [String: Int] = [:]
        var remaining = Dictionary(uniqueKeysWithValues: nodes.map { ($0, (incoming[$0] ?? []).count) })

        // Kahn's algorithm, taking nodes in name order so the result does not depend on
        // dictionary iteration.
        var ready = nodes.filter { remaining[$0] == 0 }.sorted()
        for node in ready { layer[node] = 0 }

        while let node = ready.first {
            ready.removeFirst()
            for next in (outgoing[node] ?? []).sorted() {
                layer[next] = max(layer[next] ?? 0, (layer[node] ?? 0) + 1)
                remaining[next]! -= 1
                if remaining[next] == 0 {
                    ready.append(next)
                    ready.sort()
                }
            }
        }

        // Anything still unplaced sat only on a cycle. Put it below whatever refers to it.
        for node in nodes where layer[node] == nil {
            layer[node] = (incoming[node] ?? []).compactMap { layer[$0] }.max().map { $0 + 1 } ?? 0
        }
        return layer
    }

    /// Left-to-right order within each layer, so edges cross as little as possible.
    ///
    /// A couple of passes of the barycentre heuristic — each node moves next to the average
    /// position of what refers to it — with ties broken by name so the same schema always
    /// draws the same way.
    fileprivate static func order(_ nodes: [String],
                              layers: [String: Int],
                              edges: [Edge]) -> [String: Int] {
        var byLayer: [Int: [String]] = [:]
        for node in nodes.sorted() { byLayer[layers[node] ?? 0, default: []].append(node) }

        var position: [String: Double] = [:]
        for (_, names) in byLayer {
            for (index, name) in names.enumerated() { position[name] = Double(index) }
        }

        var incoming: [String: [String]] = [:]
        for edge in edges where !edge.isBackEdge { incoming[edge.to, default: []].append(edge.from) }

        for _ in 0..<4 {
            for layer in byLayer.keys.sorted() where layer > 0 {
                let names = byLayer[layer]!
                let scored = names.map { name -> (String, Double) in
                    let parents = (incoming[name] ?? []).compactMap { position[$0] }
                    let barycentre = parents.isEmpty
                        ? position[name] ?? 0
                        : parents.reduce(0, +) / Double(parents.count)
                    return (name, barycentre)
                }
                let sorted = scored.sorted {
                    $0.1 == $1.1 ? $0.0 < $1.0 : $0.1 < $1.1
                }.map(\.0)
                byLayer[layer] = sorted
                for (index, name) in sorted.enumerated() { position[name] = Double(index) }
            }
        }

        var result: [String: Int] = [:]
        for (_, names) in byLayer {
            for (index, name) in names.enumerated() { result[name] = index }
        }
        return result
    }
}
