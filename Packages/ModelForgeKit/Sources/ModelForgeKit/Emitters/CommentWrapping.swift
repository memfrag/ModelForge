import Foundation

/// Keeps a generated comment inside the column limit.
///
/// Applied per line of the author's documentation rather than by re-flowing the whole
/// thing: a line break someone put in a doc comment is usually there on purpose, and
/// joining paragraphs to rewrap them would throw that away. Only a line that is too long
/// is broken, and only at a space.
enum CommentWrapping {

    /// The column a generated line of comment is kept within.
    ///
    /// Eighty, because a side-by-side diff, a terminal and a review comment all assume it,
    /// and generated code is read in all three more often than it is read in an editor.
    static let columnLimit = 80

    /// Break one line of documentation into as many lines as the limit requires.
    ///
    /// - Parameters:
    ///   - text: one line of documentation, with no comment marker on it.
    ///   - prefix: what each produced line begins with, such as `"/// "`.
    ///   - indent: the columns the writer will put in front of that prefix.
    /// - Returns: one line per output line, each already carrying `prefix`, and never
    ///   with trailing whitespace.
    static func lines(for text: String, prefix: String, indent: Int) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [marker(of: prefix)] }

        let available = columnLimit - indent - prefix.count
        // Indented so deeply that there is no room to wrap into. Breaking here would put
        // one word on each line, which is worse than a long line.
        guard available > 0 else { return [prefix + trimmed] }

        var result: [String] = []
        var current = ""

        for word in trimmed.split(separator: " ", omittingEmptySubsequences: true) {
            if current.isEmpty {
                // A word longer than the whole line goes on its own and overruns. Breaking
                // it would break an identifier, a URL or a symbol reference.
                current = String(word)
            } else if current.count + 1 + word.count <= available {
                current += " " + word
            } else {
                result.append(prefix + current)
                current = String(word)
            }
        }
        if !current.isEmpty { result.append(prefix + current) }
        return result
    }

    /// The marker on its own, for a blank line inside a comment. Without this the line
    /// would end in a space, which `CodeWriter` forbids and some linters flag.
    private static func marker(of prefix: String) -> String {
        var marker = prefix
        while marker.hasSuffix(" ") { marker.removeLast() }
        return marker
    }

    /// Whether a single line of source, once indented, fits.
    static func fits(_ text: String, indent: Int) -> Bool {
        indent + text.count <= columnLimit
    }
}
