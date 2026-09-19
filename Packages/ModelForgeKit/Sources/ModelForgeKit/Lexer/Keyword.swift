import Foundation

/// The DSL's reserved words.
///
/// Note what is absent: there is no `import` and no `config`. A ModelForge project is one
/// bundle sharing a single flat namespace, so files see each other without declaring it,
/// and emitter configuration lives in the project's `Config.json` rather than in source.
///
/// `Set` and `Map` are deliberately *not* keywords. They are ordinary identifiers that the
/// parser recognises contextually in a type position, which keeps them usable as field
/// names while still reserving them as type names in semantic analysis.
public enum Keyword: String, Sendable, Hashable, CaseIterable {
    case model
    case `enum`
    case union
    case `typealias`
    case `true`
    case `false`
    case null

    /// Keywords that begin a declaration. Used by parser recovery to find its feet again.
    public static let declarationStarters: Set<Keyword> = [.model, .enum, .union, .typealias]

    public var startsDeclaration: Bool {
        Self.declarationStarters.contains(self)
    }
}
