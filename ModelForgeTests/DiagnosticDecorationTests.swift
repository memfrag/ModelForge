//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Testing
import AppKit
import ModelForgeKit
@testable import ModelForge

@Suite("Diagnostic decoration")
struct DiagnosticDecorationTests {

    private func diagnostic(from start: Int,
                            to end: Int,
                            severity: Diagnostic.Severity = .error,
                            message: String = "unknown type 'Usre'",
                            notes: [Diagnostic.Note] = []) -> Diagnostic {
        Diagnostic(code: .unknownType,
                   severity: severity,
                   message: message,
                   range: SourceRange(file: SourceFileID(0),
                                      start: SourceLocation(offset: start, line: 1, column: start + 1),
                                      end: SourceLocation(offset: end, line: 1, column: end + 1)),
                   notes: notes)
    }

    // MARK: What gets underlined

    /// Two lines: `model A {` then `    x: Str`, with a trailing newline. 26 units.
    private let source = "model A {\n    x: Str\n" as NSString

    @Test("An ordinary range underlines exactly the text it covers")
    func anOrdinaryRange() {
        // `Str`, at offsets 17..<20.
        #expect(DiagnosticDecoration.range(for: diagnostic(from: 17, to: 20), in: source)
                == NSRange(location: 17, length: 3))
    }

    @Test("A problem reported where there is no token marks the word before it")
    func aZeroWidthRange() {
        // A missing closing brace is reported just past the final token, which is the line
        // break. The whole word rather than one character: a dotted underline needs some
        // width before it draws a dot at all.
        #expect(DiagnosticDecoration.range(for: diagnostic(from: 20, to: 20), in: source)
                == NSRange(location: 17, length: 3))
    }

    @Test("A range that covers only the line break is moved onto the token before it")
    func aRangeOverALineBreakAlone() {
        // The same problem, reported as a range over the newline rather than as an empty
        // one at it. Both have to end up somewhere visible.
        #expect(DiagnosticDecoration.range(for: diagnostic(from: 20, to: 21), in: source)
                == NSRange(location: 17, length: 3))
    }

    @Test("Trailing whitespace does not take the mark that belongs to the token")
    func trailingWhitespaceIsSkipped() {
        let padded = "model A {\n    x: Str   \n" as NSString
        #expect(DiagnosticDecoration.range(for: diagnostic(from: 24, to: 24), in: padded)
                == NSRange(location: 17, length: 3))
    }

    @Test("A range that covers real text as well as a line break is left alone")
    func aRangeEndingInALineBreak() {
        #expect(DiagnosticDecoration.range(for: diagnostic(from: 17, to: 21), in: source)
                == NSRange(location: 17, length: 4))
    }

    @Test("A range from a compile of longer text is clamped, not trusted")
    func aStaleRangeIsClamped() {
        // The result in hand can describe a version of the file with more text in it.
        // An NSRange past the end is a crash, not a mistake.
        #expect(DiagnosticDecoration.range(for: diagnostic(from: 17, to: 400), in: source)
                == NSRange(location: 17, length: 4))
        #expect(DiagnosticDecoration.range(for: diagnostic(from: 300, to: 400), in: source)
                == NSRange(location: 17, length: 3))
    }

    @Test("There is nothing to underline in an empty file")
    func emptyText() {
        #expect(DiagnosticDecoration.range(for: diagnostic(from: 0, to: 0), in: "") == nil)
        #expect(DiagnosticDecoration.range(for: diagnostic(from: 0, to: 5), in: "") == nil)
    }

    @Test("A file of nothing but blank lines has nothing to mark")
    func nothingButWhitespace() {
        #expect(DiagnosticDecoration.range(for: diagnostic(from: 3, to: 3), in: "\n\n\n") == nil)
    }

    @Test("Every range it returns is safe to hand to NSAttributedString, and visible")
    func everyRangeIsUsable() {
        let texts: [NSString] = ["", "\n", "x", "model A {\n    x: Str\n", "  \n  \n"]
        for text in texts {
            for start in [0, 1, 3, 19, 20, 400] {
                for end in [0, 1, 3, 19, 20, 400] where end >= start {
                    guard let range = DiagnosticDecoration.range(for: diagnostic(from: start, to: end),
                                                                 in: text) else { continue }
                    #expect(range.location >= 0)
                    #expect(range.length > 0)
                    #expect(NSMaxRange(range) <= text.length)
                }
            }
        }
    }

    // MARK: Appearance

    @Test("Severity colours match the ones the problems list uses")
    func severityColours() {
        #expect(DiagnosticDecoration.color(for: .error) == .systemRed)
        #expect(DiagnosticDecoration.color(for: .warning) == .systemOrange)
        #expect(DiagnosticDecoration.color(for: .note) == .secondaryLabelColor)
    }

    @Test("The underline is dotted and thick, so it does not read as a link")
    func underlineStyle() {
        let style = NSUnderlineStyle(rawValue: DiagnosticDecoration.underlineStyle)
        #expect(style.contains(.thick))
        #expect(style.contains(.patternDot))
        #expect(!style.contains(.byWord))
    }

    @Test("Hovering says what is wrong, and what to do about it")
    func tooltipCarriesTheHelp() {
        let plain = DiagnosticDecoration.tooltip(for: diagnostic(from: 0, to: 4))
        #expect(plain == "unknown type 'Usre'")

        let helped = DiagnosticDecoration.tooltip(
            for: diagnostic(from: 0, to: 4, notes: [Diagnostic.Note(message: "did you mean 'User'?")]))
        #expect(helped == "unknown type 'Usre'\nhelp: did you mean 'User'?")
    }
}
