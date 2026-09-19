import Foundation

/// Turns the DSL's own tokens into highlight spans.
///
/// Highlighting is driven by the real lexer rather than by regular expressions. The lexer
/// exists anyway, it is exact, and because no token spans a line the editor can re-lex
/// just the paragraph it edited on each keystroke and get the same answer as a whole-file
/// pass — no flicker, and no waiting for the debounced compile to correct the colours.
public enum DSLHighlightClassifier {

    public static func spans(for tokens: [Token]) -> [HighlightSpan] {
        var spans: [HighlightSpan] = []
        var state = State()

        for token in tokens where !token.isEndOfFile {
            if token.isAtStartOfLine, state.depth == 0 {
                state.expectsType = false
            }

            if let kind = classify(token, state: &state) {
                spans.append(HighlightSpan(kind: kind, range: token.range.utf16Range))
            }
            state.advance(past: token)
        }

        return spans
    }

    /// What the classifier needs to remember between tokens.
    ///
    /// Purely local context — which is enough, because the grammar puts a type immediately
    /// after a `:`, a `(` or an opening bracket, and nowhere else.
    private struct State {
        var expectsType = false
        var afterAt = false
        var afterDot = false
        var afterDeclarationKeyword = false
        var afterTypeAlias = false
        var depth = 0

        mutating func advance(past token: Token) {
            afterAt = token.is(.at)
            afterDot = token.is(.dot)
            afterDeclarationKeyword = token.keyword?.startsDeclaration == true
            if token.is(.typealias) { afterTypeAlias = true }

            switch token.kind {
            case .punctuation(.colon):
                expectsType = true
            case .punctuation(.equals):
                // In a type alias the type follows the '='; in a field it is a default.
                expectsType = afterTypeAlias
                afterTypeAlias = false
            case .punctuation(.leftBracket), .punctuation(.leftAngle), .punctuation(.leftParen):
                expectsType = true
                depth += 1
            case .punctuation(.rightBracket), .punctuation(.rightAngle), .punctuation(.rightParen):
                depth = max(0, depth - 1)
                if depth == 0 { expectsType = false }
            case .identifier where afterDeclarationKeyword:
                break
            default:
                break
            }
        }
    }

    private static func classify(_ token: Token, state: inout State) -> HighlightKind? {
        switch token.kind {
        case .keyword(.true), .keyword(.false), .keyword(.null):
            return .keyword
        case .keyword:
            return .keyword
        case .string:
            return .string
        case .integer, .float:
            return .number
        case .lineComment:
            return .comment
        case .docComment:
            return .docComment
        case .punctuation:
            return .punctuation
        case .unknown, .endOfFile:
            return nil
        case .identifier:
            if state.afterAt { return .attribute }
            if state.afterDot { return .enumCase }
            if state.afterDeclarationKeyword { return .declarationName }
            if state.expectsType { return .typeName }
            return .fieldName
        }
    }
}
