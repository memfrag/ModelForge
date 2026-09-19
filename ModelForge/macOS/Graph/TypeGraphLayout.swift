//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import AppKit
import ModelForgeKit

/// Where each node in a `TypeGraph` actually sits.
///
/// The Kit works out the structure — which layer a type belongs to and where in that layer
/// — because that is the part that can be wrong without looking at a screen. This turns
/// that into rectangles, which needs to know how wide a name renders and is therefore the
/// app's business.
struct TypeGraphLayout: Equatable {

    struct PositionedNode: Equatable, Identifiable {
        let node: TypeGraph.Node
        let frame: CGRect

        var id: String { node.name }

        var topCentre: CGPoint { CGPoint(x: frame.midX, y: frame.minY) }
        var bottomCentre: CGPoint { CGPoint(x: frame.midX, y: frame.maxY) }
    }

    struct PositionedEdge: Equatable, Identifiable {
        let edge: TypeGraph.Edge
        let start: CGPoint
        let end: CGPoint
        /// Pulled straight out of the node it leaves and straight into the one it meets,
        /// so a line reads as leaving a bottom edge rather than shooting off at an angle.
        let control1: CGPoint
        let control2: CGPoint

        var id: String { edge.id }

        /// Where the label sits: the curve at its halfway point, which for a cubic is a
        /// weighted average of its four points rather than the midpoint of its ends.
        var midpoint: CGPoint {
            CGPoint(x: (start.x + 3 * control1.x + 3 * control2.x + end.x) / 8,
                    y: (start.y + 3 * control1.y + 3 * control2.y + end.y) / 8)
        }
    }

    var nodes: [PositionedNode] = []
    var edges: [PositionedEdge] = []
    /// The whole drawing, including its margin.
    var size: CGSize = .zero

    var isEmpty: Bool { nodes.isEmpty }

    /// An empty layout, for before the first compile lands.
    init() {}

    // MARK: Metrics

    static let nodeHeight: CGFloat = 30
    static let horizontalGap: CGFloat = 20
    static let verticalGap: CGFloat = 52
    static let margin: CGFloat = 32
    static let minimumNodeWidth: CGFloat = 76
    /// Room for the kind icon and the padding either side of the name.
    static let nodeChrome: CGFloat = 40

    static func width(of name: String, font: NSFont) -> CGFloat {
        let measured = (name as NSString).size(withAttributes: [.font: font]).width
        return max(minimumNodeWidth, ceil(measured) + nodeChrome)
    }

    // MARK: Building

    /// Lay the graph out top to bottom, one row per layer.
    ///
    /// Rows are centred against the widest one, so a schema with a single root does not end
    /// up with everything hanging off the left edge.
    init(graph: TypeGraph, font: NSFont) {
        guard !graph.isEmpty else { return }

        var rows: [[(node: TypeGraph.Node, width: CGFloat)]] = []
        for layer in 0..<graph.layerCount {
            rows.append(graph.nodes(inLayer: layer).map {
                ($0, Self.width(of: $0.name, font: font))
            })
        }

        let rowWidths = rows.map { row in
            row.map(\.width).reduce(0, +)
                + Self.horizontalGap * CGFloat(max(0, row.count - 1))
        }
        let widest = rowWidths.max() ?? 0

        var positioned: [PositionedNode] = []
        for (index, row) in rows.enumerated() {
            var x = Self.margin + (widest - rowWidths[index]) / 2
            let y = Self.margin + CGFloat(index) * (Self.nodeHeight + Self.verticalGap)

            for entry in row {
                positioned.append(PositionedNode(
                    node: entry.node,
                    frame: CGRect(x: x, y: y, width: entry.width, height: Self.nodeHeight)))
                x += entry.width + Self.horizontalGap
            }
        }

        nodes = positioned
        size = CGSize(
            width: widest + Self.margin * 2,
            height: Self.margin * 2 + CGFloat(rows.count) * Self.nodeHeight
                + CGFloat(max(0, rows.count - 1)) * Self.verticalGap)

        let byName = Dictionary(uniqueKeysWithValues: positioned.map { ($0.node.name, $0) })
        edges = graph.edges.compactMap { edge in
            guard let from = byName[edge.from], let to = byName[edge.to] else { return nil }
            // A back edge points up the graph, so it leaves the top of its source and
            // arrives at the bottom of its target — the opposite of every other line.
            let goingDown = from.frame.midY < to.frame.midY
            let start = goingDown ? from.bottomCentre : from.topCentre
            let end = goingDown ? to.topCentre : to.bottomCentre
            let lift = max(16, abs(end.y - start.y) / 2) * (goingDown ? 1 : -1)
            return PositionedEdge(
                edge: edge,
                start: start,
                end: end,
                control1: CGPoint(x: start.x, y: start.y + lift),
                control2: CGPoint(x: end.x, y: end.y - lift))
        }
    }

    // MARK: Lookup

    func node(at point: CGPoint) -> TypeGraph.Node? {
        nodes.first { $0.frame.contains(point) }?.node
    }

    func frame(of name: String) -> CGRect? {
        nodes.first { $0.node.name == name }?.frame
    }
}
