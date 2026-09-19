import Foundation

/// A one-token-lookahead cursor over a file's tokens.
///
/// Line comments are dropped on the way in; documentation comments are kept, because the
/// parser attaches them to the declaration or member that follows.
struct TokenCursor {

    private let tokens: [Token]
    private(set) var index = 0

    init(_ tokens: [Token]) {
        var kept = tokens.filter { token in
            if case .lineComment = token.kind { return false }
            return true
        }
        if kept.isEmpty || !kept[kept.count - 1].isEndOfFile {
            // Defensive: every cursor must end on an end-of-file token so `current` is
            // always valid without bounds checks at every call site.
            let location = SourceLocation(offset: 0, line: 1, column: 1)
            let file = tokens.first?.range.file ?? SourceFileID(0)
            kept.append(Token(kind: .endOfFile,
                              range: SourceRange(file: file, start: location, end: location),
                              isAtStartOfLine: true))
        }
        self.tokens = kept
    }

    var current: Token {
        tokens[min(index, tokens.count - 1)]
    }

    func peek(_ distance: Int = 1) -> Token {
        tokens[min(index + distance, tokens.count - 1)]
    }

    var isAtEnd: Bool {
        current.isEndOfFile
    }

    /// The range to point a "something is missing here" diagnostic at: the end of the
    /// previous token, so the caret lands where the missing text should have been rather
    /// than on the unrelated token that follows.
    var endOfPreviousToken: SourceRange {
        guard index > 0 else { return current.range.collapsedToStart }
        let previous = tokens[index - 1]
        return SourceRange(file: previous.range.file,
                           start: previous.range.end,
                           end: previous.range.end)
    }

    @discardableResult
    mutating func advance() -> Token {
        let token = current
        if index < tokens.count - 1 { index += 1 }
        return token
    }

    func check(_ punctuation: Punctuation) -> Bool {
        current.is(punctuation)
    }

    func check(_ keyword: Keyword) -> Bool {
        current.is(keyword)
    }

    /// Consume the token if it matches, otherwise leave the cursor alone.
    mutating func match(_ punctuation: Punctuation) -> Token? {
        guard current.is(punctuation) else { return nil }
        return advance()
    }

    mutating func match(_ keyword: Keyword) -> Token? {
        guard current.is(keyword) else { return nil }
        return advance()
    }

    var isAtDeclarationStart: Bool {
        current.keyword?.startsDeclaration == true
    }
}
