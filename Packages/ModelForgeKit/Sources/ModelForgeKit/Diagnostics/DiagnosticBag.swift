import Foundation

/// Collects diagnostics during a compile.
///
/// Every phase takes this `inout` rather than throwing, because the whole design depends
/// on continuing past errors: the previews must keep rendering while the user is
/// mid-keystroke.
public struct DiagnosticBag: Sendable {

    public private(set) var diagnostics: [Diagnostic] = []

    public init() {}

    public mutating func add(_ diagnostic: Diagnostic) {
        diagnostics.append(diagnostic)
    }

    public mutating func error(_ code: DiagnosticCode,
                               _ message: String,
                               at range: SourceRange,
                               notes: [Diagnostic.Note] = [],
                               fixIts: [Diagnostic.FixIt] = []) {
        add(Diagnostic(code: code, severity: .error, message: message,
                       range: range, notes: notes, fixIts: fixIts))
    }

    public mutating func warning(_ code: DiagnosticCode,
                                 _ message: String,
                                 at range: SourceRange,
                                 notes: [Diagnostic.Note] = [],
                                 fixIts: [Diagnostic.FixIt] = []) {
        add(Diagnostic(code: code, severity: .warning, message: message,
                       range: range, notes: notes, fixIts: fixIts))
    }

    public var hasErrors: Bool {
        diagnostics.contains { $0.severity == .error }
    }

    public var errorCount: Int {
        diagnostics.count { $0.severity == .error }
    }

    public var warningCount: Int {
        diagnostics.count { $0.severity == .warning }
    }

    /// File order, then position. Deterministic, so snapshot tests are stable.
    public func sorted() -> [Diagnostic] {
        diagnostics.sorted { lhs, rhs in
            if lhs.range.file != rhs.range.file {
                return lhs.range.file < rhs.range.file
            }
            if lhs.range.start != rhs.range.start {
                return lhs.range.start < rhs.range.start
            }
            return lhs.code.rawValue < rhs.code.rawValue
        }
    }
}
