import Foundation

/// Renders a diagnostic in the terminal style the DSL proposal specifies (§17):
///
///     user.model:8:12
///
///         manager: Usre?
///                  ^^^^
///
///     error: unknown type 'Usre'
///     help: did you mean 'User'?
///
/// This one renderer backs the problems list's Copy action, the future `modelgen` CLI,
/// and the expected output of the semantic test fixtures — so those fixtures double as a
/// readable specification of the diagnostic experience.
public enum DiagnosticRenderer {

    /// Spaces a tab expands to when aligning the caret under the source line.
    private static let tabWidth = 4
    private static let gutter = "    "

    public static func render(_ diagnostic: Diagnostic,
                              in files: [SourceFileID: SourceFile]) -> String {
        var lines: [String] = []
        let file = files[diagnostic.range.file]
        let name = file?.name ?? "<unknown>"
        let start = diagnostic.range.start

        lines.append("\(name):\(start.line):\(start.column)")

        if let file {
            lines.append("")
            lines.append(contentsOf: sourceExcerpt(for: diagnostic.range, in: file))
            lines.append("")
        }

        lines.append("\(diagnostic.severity.label): \(diagnostic.message)")

        for note in diagnostic.notes {
            lines.append("help: \(note.message)")
            if let noteRange = note.range,
               let noteFile = files[noteRange.file],
               noteRange.file != diagnostic.range.file || noteRange.start.line != start.line {
                lines.append("\(gutter)\(noteFile.name):\(noteRange.start.line):\(noteRange.start.column)")
            }
        }

        return lines.joined(separator: "\n")
    }

    public static func render(_ diagnostics: [Diagnostic],
                              in files: [SourceFileID: SourceFile]) -> String {
        diagnostics
            .map { render($0, in: files) }
            .joined(separator: "\n\n")
    }

    /// The offending line, indented, with a caret run under the offending span.
    ///
    /// Only the first line of a multi-line range is underlined; the caret then runs to
    /// the end of that line, which reads better than underlining nothing.
    private static func sourceExcerpt(for range: SourceRange, in file: SourceFile) -> [String] {
        let lineNumber = range.start.line
        let raw = file.text(ofLine: lineNumber)
        let expanded = raw.replacingOccurrences(of: "\t", with: String(repeating: " ", count: tabWidth))

        let lineRange = file.lineTable.range(ofLine: lineNumber)
        let startInLine = max(0, range.start.offset - lineRange.lowerBound)
        let endInLine = range.end.location(clampedToLineEnding: lineRange, start: range.start.offset)

        let leading = visualWidth(of: raw, upTo: startInLine)
        let spanWidth = max(1, visualWidth(of: raw, from: startInLine, upTo: endInLine))

        return [
            gutter + expanded,
            gutter + String(repeating: " ", count: leading) + String(repeating: "^", count: spanWidth)
        ]
    }

    /// Width of the first `count` UTF-16 units of `text`, with tabs expanded.
    private static func visualWidth(of text: String, upTo count: Int) -> Int {
        visualWidth(of: text, from: 0, upTo: count)
    }

    private static func visualWidth(of text: String, from start: Int, upTo end: Int) -> Int {
        let units = Array(text.utf16)
        var width = 0
        var index = max(0, start)
        let limit = min(end, units.count)
        while index < limit {
            width += units[index] == 0x09 ? tabWidth : 1
            index += 1
        }
        return width
    }
}

private extension SourceLocation {

    /// The end offset within a line, clamped so a range spilling past the newline
    /// underlines to the end of the line rather than running off it.
    func location(clampedToLineEnding lineRange: Range<Int>, start: Int) -> Int {
        let end = min(offset, lineRange.upperBound)
        return max(end - lineRange.lowerBound, start - lineRange.lowerBound)
    }
}
