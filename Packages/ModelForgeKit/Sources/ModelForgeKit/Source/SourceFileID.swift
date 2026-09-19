import Foundation

/// Identifies one source file within a compilation.
///
/// Ranges carry an id rather than a path so that diagnostics stay cheap to copy and
/// comparable, and so the UI can map a diagnostic back to the file it belongs to
/// without string matching.
public struct SourceFileID: Hashable, Sendable, Comparable {

    public let rawValue: Int

    public init(_ rawValue: Int) {
        self.rawValue = rawValue
    }

    public static func < (lhs: SourceFileID, rhs: SourceFileID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
