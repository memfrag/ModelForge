import Foundation

public struct Token: Sendable, Hashable {

    public enum Kind: Sendable, Hashable {
        case identifier(String)
        /// The decoded contents of a string literal, with escapes resolved.
        case string(String)
        /// Numeric literals keep their **lexeme**, never a parsed `Double`. Re-emitting the
        /// spelling the author wrote is what keeps generated output byte-stable.
        case integer(lexeme: String)
        case float(lexeme: String)
        case keyword(Keyword)
        case punctuation(Punctuation)
        case lineComment
        /// A `///` comment, with the marker and one optional following space stripped.
        case docComment(String)
        /// A character the lexer does not recognise. Produced instead of throwing, so one
        /// stray byte never blanks the previews.
        case unknown
        case endOfFile
    }

    public let kind: Kind
    public let range: SourceRange
    /// Whether this is the first token on its line. Parser recovery resynchronises on
    /// this, and the canonical one-member-per-line style makes it a reliable boundary.
    public let isAtStartOfLine: Bool

    public init(kind: Kind, range: SourceRange, isAtStartOfLine: Bool) {
        self.kind = kind
        self.range = range
        self.isAtStartOfLine = isAtStartOfLine
    }

    // MARK: Convenience

    public var identifierText: String? {
        if case .identifier(let text) = kind { return text }
        return nil
    }

    public var keyword: Keyword? {
        if case .keyword(let keyword) = kind { return keyword }
        return nil
    }

    public func `is`(_ punctuation: Punctuation) -> Bool {
        if case .punctuation(let actual) = kind { return actual == punctuation }
        return false
    }

    public func `is`(_ keyword: Keyword) -> Bool {
        if case .keyword(let actual) = kind { return actual == keyword }
        return false
    }

    public var isEndOfFile: Bool {
        if case .endOfFile = kind { return true }
        return false
    }

    /// Comments are kept in the token stream for syntax highlighting, and skipped by the
    /// parser's cursor.
    public var isTrivia: Bool {
        switch kind {
        case .lineComment, .docComment: true
        default: false
        }
    }

    /// How the token reads in a diagnostic such as "expected ':', found '}'".
    public var describedForDiagnostic: String {
        switch kind {
        case .identifier(let text): "'\(text)'"
        case .string: "a string literal"
        case .integer: "a number"
        case .float: "a number"
        case .keyword(let keyword): "'\(keyword.rawValue)'"
        case .punctuation(let punctuation): "'\(punctuation.rawValue)'"
        case .lineComment: "a comment"
        case .docComment: "a documentation comment"
        case .unknown: "an unexpected character"
        case .endOfFile: "end of file"
        }
    }
}
