import Foundation

/// One problem found while compiling, anchored to an exact span of source.
public struct Diagnostic: Sendable, Hashable, Identifiable {

    public enum Severity: Int, Sendable, Hashable, Comparable, CaseIterable {
        case note
        case warning
        case error

        public static func < (lhs: Severity, rhs: Severity) -> Bool {
            lhs.rawValue < rhs.rawValue
        }

        public var label: String {
            switch self {
            case .note: "note"
            case .warning: "warning"
            case .error: "error"
            }
        }
    }

    /// Supplementary information, rendered as `help:` beneath the main message.
    public struct Note: Sendable, Hashable {
        public let message: String
        /// Where the note points, when it refers to another piece of source such as a
        /// first declaration that a duplicate collides with.
        public let range: SourceRange?

        public init(message: String, range: SourceRange? = nil) {
            self.message = message
            self.range = range
        }
    }

    /// A mechanical correction the editor can apply.
    public struct FixIt: Sendable, Hashable {
        public let message: String
        public let range: SourceRange
        public let replacement: String

        public init(message: String, range: SourceRange, replacement: String) {
            self.message = message
            self.range = range
            self.replacement = replacement
        }
    }

    public let code: DiagnosticCode
    public let severity: Severity
    public let message: String
    public let range: SourceRange
    public let notes: [Note]
    public let fixIts: [FixIt]

    public init(code: DiagnosticCode,
                severity: Severity? = nil,
                message: String,
                range: SourceRange,
                notes: [Note] = [],
                fixIts: [FixIt] = []) {
        self.code = code
        self.severity = severity ?? code.severityHint
        self.message = message
        self.range = range
        self.notes = notes
        self.fixIts = fixIts
    }

    /// Stable across recompiles of identical source, so SwiftUI list selection survives
    /// a keystroke that doesn't change the problem.
    public var id: String {
        "\(range.file.rawValue):\(range.start.offset):\(range.end.offset):\(code.rawValue)"
    }
}
