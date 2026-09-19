import Foundation

/// Finds types that contain themselves.
///
/// "Contains" here means *directly*, without an intervening collection: `[Node]` and
/// `Map<String, Node>` are fine because both platforms store their elements out of line,
/// while `Node` or `Node?` as a field is not.
///
/// The distinction between the two outcomes matters:
///
/// - A cycle made only of **models** is an error. A Swift `struct` containing itself has
///   no finite size, and although Kotlin would accept it, the language has to mean the
///   same thing on both platforms.
/// - A cycle passing through a **union** is fine. Marking the union `indirect` in Swift
///   breaks it, and Kotlin needs nothing, so those unions are flagged rather than rejected.
enum RecursionChecker {

    struct Result {
        /// Unions that must be emitted as `indirect` in Swift.
        var recursiveUnions: Set<String> = []
        /// Models that form a cycle with no union to break it.
        var illegalModelCycles: [[String]] = []
    }

    /// - Parameter containment: for each declared type, the types it directly contains.
    /// - Parameter kinds: what each declared name is.
    static func check(containment: [String: Set<String>],
                      kinds: [String: NamedKind]) -> Result {
        var result = Result()

        for component in stronglyConnectedComponents(in: containment) {
            let isCycle = component.count > 1
                || component.first.map { containment[$0]?.contains($0) == true } == true
            guard isCycle else { continue }

            let unions = component.filter { kinds[$0] == .union }
            if unions.isEmpty {
                result.illegalModelCycles.append(component.sorted())
            } else {
                result.recursiveUnions.formUnion(unions)
            }
        }

        return result
    }

    /// Tarjan's algorithm, written iteratively so a deeply nested schema cannot blow the
    /// stack.
    private static func stronglyConnectedComponents(in graph: [String: Set<String>]) -> [[String]] {
        var index = 0
        var indices: [String: Int] = [:]
        var lowLinks: [String: Int] = [:]
        var onStack: Set<String> = []
        var stack: [String] = []
        var components: [[String]] = []

        // Deterministic iteration order keeps diagnostics stable between runs.
        for root in graph.keys.sorted() where indices[root] == nil {
            var work: [(node: String, successors: [String], position: Int)] = [
                (root, (graph[root] ?? []).sorted(), 0)
            ]
            indices[root] = index
            lowLinks[root] = index
            index += 1
            stack.append(root)
            onStack.insert(root)

            while var frame = work.popLast() {
                if frame.position < frame.successors.count {
                    let successor = frame.successors[frame.position]
                    frame.position += 1
                    work.append(frame)

                    if indices[successor] == nil {
                        indices[successor] = index
                        lowLinks[successor] = index
                        index += 1
                        stack.append(successor)
                        onStack.insert(successor)
                        work.append((successor, (graph[successor] ?? []).sorted(), 0))
                    } else if onStack.contains(successor) {
                        lowLinks[frame.node] = min(lowLinks[frame.node]!, indices[successor]!)
                    }
                    continue
                }

                if lowLinks[frame.node] == indices[frame.node] {
                    var component: [String] = []
                    while let node = stack.popLast() {
                        onStack.remove(node)
                        component.append(node)
                        if node == frame.node { break }
                    }
                    components.append(component)
                }

                // Propagate this frame's low-link up to the caller, which is now on top
                // of the work stack.
                if let parent = work.last?.node,
                   let parentLow = lowLinks[parent],
                   let childLow = lowLinks[frame.node] {
                    lowLinks[parent] = min(parentLow, childLow)
                }
            }
        }

        return components
    }
}
