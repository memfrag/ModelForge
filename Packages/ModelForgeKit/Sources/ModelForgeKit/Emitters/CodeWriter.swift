import Foundation

/// Builds source text line by line, tracking indentation.
///
/// Every rule here exists to make output byte-identical from one run to the next: `\n`
/// only, exactly one trailing newline, no trailing whitespace on any line, and never two
/// blank lines in a row. Determinism is what lets Generate skip writing a file whose
/// contents have not changed, which in turn keeps Xcode and Gradle from rebuilding.
struct CodeWriter {

    private var lines: [String] = []
    private var level = 0
    private let indentation: String

    init(indentation: String = "    ") {
        self.indentation = indentation
    }

    /// How many columns `line` will put in front of whatever it is given.
    ///
    /// Comment wrapping needs it: a doc comment that fits at the top level does not
    /// necessarily fit once it is a field's, two levels in.
    var indentWidth: Int {
        indentation.count * level
    }

    mutating func line(_ text: String) {
        guard !text.isEmpty else {
            blank()
            return
        }
        lines.append(String(repeating: indentation, count: level) + text)
    }

    /// Several lines at the current indentation.
    mutating func lines(_ texts: [String]) {
        for text in texts { line(text) }
    }

    /// A blank separator. Consecutive calls collapse, and a leading one is dropped, so
    /// callers can ask for spacing without checking whether it is already there.
    mutating func blank() {
        guard let last = lines.last, !last.isEmpty else { return }
        lines.append("")
    }

    mutating func indented(_ body: (inout CodeWriter) -> Void) {
        level += 1
        body(&self)
        level -= 1
    }

    /// `header {` … `}`, with the body indented.
    mutating func block(_ header: String, _ body: (inout CodeWriter) -> Void) {
        line("\(header) {")
        indented(body)
        line("}")
    }

    var text: String {
        var result = lines
        while let last = result.last, last.isEmpty {
            result.removeLast()
        }
        return result.joined(separator: "\n") + "\n"
    }
}
