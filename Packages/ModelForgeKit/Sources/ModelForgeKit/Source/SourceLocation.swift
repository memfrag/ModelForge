import Foundation

/// A point in a source file.
///
/// `offset` is in **UTF-16 code units**, which is what `NSTextView` and `NSRange` use, so
/// a range converts to an `NSRange` without any conversion cost. `line` and `column` are
/// 1-based and exist for diagnostics. Columns count UTF-16 units, which is exact for
/// ASCII and can drift inside string literals containing astral-plane characters.
public struct SourceLocation: Sendable, Hashable, Comparable, CustomStringConvertible {

    public let offset: Int
    public let line: Int
    public let column: Int

    public init(offset: Int, line: Int, column: Int) {
        self.offset = offset
        self.line = line
        self.column = column
    }

    public init(offset: Int, in lineTable: LineTable) {
        let line = lineTable.line(containing: offset)
        self.offset = offset
        self.line = line
        self.column = offset - lineTable.lineStarts[line - 1] + 1
    }

    public static func < (lhs: SourceLocation, rhs: SourceLocation) -> Bool {
        lhs.offset < rhs.offset
    }

    public var description: String {
        "\(line):\(column)"
    }
}

/// A half-open span of source text, tagged with the file it belongs to.
public struct SourceRange: Sendable, Hashable {

    public let file: SourceFileID
    public let start: SourceLocation
    public let end: SourceLocation

    public init(file: SourceFileID, start: SourceLocation, end: SourceLocation) {
        self.file = file
        self.start = start
        self.end = end
    }

    /// The span as UTF-16 offsets, ready to become an `NSRange`.
    public var utf16Range: Range<Int> {
        start.offset..<max(start.offset, end.offset)
    }

    public var isEmpty: Bool {
        end.offset <= start.offset
    }

    /// The smallest range covering both operands. They must be in the same file.
    public func union(_ other: SourceRange) -> SourceRange {
        precondition(file == other.file, "Cannot union ranges from different files")
        return SourceRange(file: file,
                           start: Swift.min(start, other.start),
                           end: Swift.max(end, other.end))
    }

    /// A zero-length range at `start`, used for diagnostics that point at a position
    /// rather than at existing text, such as a missing closing brace.
    public var collapsedToStart: SourceRange {
        SourceRange(file: file, start: start, end: start)
    }
}
