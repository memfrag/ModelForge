import Foundation

/// Turns source text into tokens.
///
/// Two properties matter more than anything else here:
///
/// 1. **It never throws.** An unrecognised character becomes an `.unknown` token plus a
///    diagnostic; an unterminated string ends at the newline. The previews must keep
///    rendering while the user is halfway through typing.
/// 2. **No token spans a line.** That is what lets the editor re-lex just the paragraph it
///    edited on every keystroke and get exactly the same answer as a whole-file lex, with
///    no flicker and no stale colouring. It is also why block comments are deliberately
///    not supported.
public struct Lexer {

    private let units: [UInt16]
    private let fileID: SourceFileID
    private let lineTable: LineTable

    private var index: Int = 0
    private var atStartOfLine = true

    // MARK: Entry points

    /// Lex an entire file.
    public static func tokenize(_ file: SourceFile, diagnostics: inout DiagnosticBag) -> [Token] {
        var lexer = Lexer(units: file.utf16, fileID: file.id, lineTable: file.lineTable)
        return lexer.run(diagnostics: &diagnostics)
    }

    /// Lex a sub-range of a file, for incremental syntax highlighting.
    ///
    /// The caller passes a range snapped to line boundaries. Because tokens never span
    /// lines, the result is identical to the corresponding slice of a full lex.
    public static func tokenize(_ file: SourceFile, in range: Range<Int>) -> [Token] {
        let lower = max(0, min(range.lowerBound, file.utf16.count))
        let upper = max(lower, min(range.upperBound, file.utf16.count))
        var lexer = Lexer(units: file.utf16, fileID: file.id, lineTable: file.lineTable)
        lexer.index = lower
        var throwaway = DiagnosticBag()
        return lexer.run(diagnostics: &throwaway, upTo: upper, includeEndOfFile: false)
    }

    private init(units: [UInt16], fileID: SourceFileID, lineTable: LineTable) {
        self.units = units
        self.fileID = fileID
        self.lineTable = lineTable
    }

    // MARK: Driver

    private mutating func run(diagnostics: inout DiagnosticBag,
                              upTo limit: Int? = nil,
                              includeEndOfFile: Bool = true) -> [Token] {
        let end = limit ?? units.count
        var tokens: [Token] = []
        while index < end {
            skipWhitespace(upTo: end)
            guard index < end else { break }
            if let token = scanToken(diagnostics: &diagnostics, limit: end) {
                tokens.append(token)
            }
        }
        if includeEndOfFile {
            let location = SourceLocation(offset: units.count, in: lineTable)
            tokens.append(Token(kind: .endOfFile,
                                range: SourceRange(file: fileID, start: location, end: location),
                                isAtStartOfLine: atStartOfLine))
        }
        return tokens
    }

    private mutating func skipWhitespace(upTo end: Int) {
        while index < end {
            let unit = units[index]
            if unit == 0x0A {
                atStartOfLine = true
                index += 1
            } else if unit == 0x20 || unit == 0x09 || unit == 0x0D {
                index += 1
            } else {
                break
            }
        }
    }

    private mutating func scanToken(diagnostics: inout DiagnosticBag, limit: Int) -> Token? {
        let start = index
        let wasAtStartOfLine = atStartOfLine
        atStartOfLine = false
        let unit = units[index]

        let kind: Token.Kind
        switch unit {
        case 0x2F where peek(1, limit: limit) == 0x2F:      // "//"
            kind = scanComment(limit: limit)

        case 0x22:                                          // '"'
            kind = scanString(diagnostics: &diagnostics, limit: limit, start: start)

        case 0x30...0x39:                                   // 0-9
            kind = scanNumber(limit: limit)

        case 0x2D where isDigit(peek(1, limit: limit)):     // '-' followed by a digit
            kind = scanNumber(limit: limit)

        default:
            if isIdentifierStart(unit) {
                kind = scanIdentifierOrKeyword(limit: limit)
            } else if let punctuation = Punctuation(scalar: unit) {
                index += 1
                kind = .punctuation(punctuation)
            } else {
                index += 1
                kind = .unknown
                diagnostics.error(.invalidCharacter,
                                  "unexpected character \(quoted(units[start]))",
                                  at: range(start, index))
            }
        }

        return Token(kind: kind, range: range(start, index), isAtStartOfLine: wasAtStartOfLine)
    }

    // MARK: Scanners

    /// `//` to end of line, or `///` for documentation.
    private mutating func scanComment(limit: Int) -> Token.Kind {
        let isDoc = peek(2, limit: limit) == 0x2F && peek(3, limit: limit) != 0x2F
        index += isDoc ? 3 : 2
        let textStart = index
        while index < limit, units[index] != 0x0A {
            index += 1
        }
        guard isDoc else { return .lineComment }

        var slice = Array(units[textStart..<index])
        // Drop exactly one leading space, so "/// Text" and "///Text" agree.
        if slice.first == 0x20 { slice.removeFirst() }
        // Trailing whitespace would otherwise leak into generated doc comments.
        while let last = slice.last, last == 0x20 || last == 0x09 || last == 0x0D {
            slice.removeLast()
        }
        return .docComment(String(decoding: slice, as: UTF16.self))
    }

    /// A double-quoted string. An unterminated one ends at the newline rather than eating
    /// the rest of the file, which keeps the damage from a missing quote to one line.
    private mutating func scanString(diagnostics: inout DiagnosticBag,
                                     limit: Int,
                                     start: Int) -> Token.Kind {
        index += 1
        var scalars: [UInt16] = []
        var terminated = false

        while index < limit {
            let unit = units[index]
            if unit == 0x0A { break }
            if unit == 0x22 {
                index += 1
                terminated = true
                break
            }
            if unit == 0x5C, index + 1 < limit {       // backslash
                let escape = units[index + 1]
                index += 2
                switch escape {
                case 0x6E: scalars.append(0x0A)        // \n
                case 0x74: scalars.append(0x09)        // \t
                case 0x72: scalars.append(0x0D)        // \r
                case 0x22: scalars.append(0x22)        // \"
                case 0x5C: scalars.append(0x5C)        // backslash
                case 0x30: scalars.append(0x00)        // \0
                default:
                    scalars.append(escape)
                    diagnostics.warning(.invalidEscape,
                                        "unrecognised escape sequence \(quoted(escape, prefixedByBackslash: true))",
                                        at: range(index - 2, index))
                }
                continue
            }
            scalars.append(unit)
            index += 1
        }

        if !terminated {
            diagnostics.error(.unterminatedString,
                              "unterminated string literal",
                              at: range(start, index))
        }
        return .string(String(decoding: scalars, as: UTF16.self))
    }

    /// An integer, or a float when a `.` is followed by another digit.
    ///
    /// The digit lookahead matters: `1.active` must lex as `1` `.` `active`, not as a
    /// malformed float.
    private mutating func scanNumber(limit: Int) -> Token.Kind {
        let start = index
        if units[index] == 0x2D { index += 1 }
        while index < limit, isDigit(units[index]) || units[index] == 0x5F {
            index += 1
        }

        var isFloat = false
        if index < limit, units[index] == 0x2E, isDigit(peek(1, limit: limit)) {
            isFloat = true
            index += 1
            while index < limit, isDigit(units[index]) || units[index] == 0x5F {
                index += 1
            }
        }

        // Exponent: 1e9, 1.5E-3
        if index < limit, units[index] == 0x65 || units[index] == 0x45 {
            let afterExponent = peek(1, limit: limit)
            let signed = afterExponent == 0x2B || afterExponent == 0x2D
            if isDigit(signed ? peek(2, limit: limit) : afterExponent) {
                isFloat = true
                index += signed ? 2 : 1
                while index < limit, isDigit(units[index]) {
                    index += 1
                }
            }
        }

        let lexeme = String(decoding: Array(units[start..<index]), as: UTF16.self)
        return isFloat ? .float(lexeme: lexeme) : .integer(lexeme: lexeme)
    }

    private mutating func scanIdentifierOrKeyword(limit: Int) -> Token.Kind {
        let start = index
        while index < limit, isIdentifierContinuation(units[index]) {
            index += 1
        }
        let text = String(decoding: Array(units[start..<index]), as: UTF16.self)
        if let keyword = Keyword(rawValue: text) {
            return .keyword(keyword)
        }
        return .identifier(text)
    }

    // MARK: Helpers

    private func peek(_ distance: Int, limit: Int) -> UInt16? {
        let target = index + distance
        return target < limit ? units[target] : nil
    }

    private func isDigit(_ unit: UInt16?) -> Bool {
        guard let unit else { return false }
        return unit >= 0x30 && unit <= 0x39
    }

    private func isIdentifierStart(_ unit: UInt16) -> Bool {
        (unit >= 0x41 && unit <= 0x5A)      // A-Z
            || (unit >= 0x61 && unit <= 0x7A)   // a-z
            || unit == 0x5F                     // _
            || unit >= 0x80                     // let sema judge non-ASCII names
    }

    private func isIdentifierContinuation(_ unit: UInt16) -> Bool {
        isIdentifierStart(unit) || (unit >= 0x30 && unit <= 0x39)
    }

    private func range(_ start: Int, _ end: Int) -> SourceRange {
        SourceRange(file: fileID,
                    start: SourceLocation(offset: start, in: lineTable),
                    end: SourceLocation(offset: end, in: lineTable))
    }

    private func quoted(_ unit: UInt16, prefixedByBackslash: Bool = false) -> String {
        let character = String(decoding: [unit], as: UTF16.self)
        return prefixedByBackslash ? "'\\\(character)'" : "'\(character)'"
    }
}
