import Foundation

/// A kind of thing worth colouring.
///
/// Shared by all three languages — the DSL, and the Swift and Kotlin previews — so the
/// editor theme is one set of colours rather than three.
public enum HighlightKind: String, Sendable, Hashable, CaseIterable {
    case keyword
    /// The name being declared, as in `model **User**`.
    case declarationName
    /// A field, property or parameter name.
    case fieldName
    case typeName
    case enumCase
    /// `@json`, `@Serializable`, `@available`.
    case attribute
    case string
    case number
    case comment
    case docComment
    case punctuation
}

/// A range of source to colour. Offsets are UTF-16 code units, so a span converts to an
/// `NSRange` with no conversion at all.
public struct HighlightSpan: Sendable, Hashable {
    public let kind: HighlightKind
    public let range: Range<Int>

    public init(kind: HighlightKind, range: Range<Int>) {
        self.kind = kind
        self.range = range
    }
}
