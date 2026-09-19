//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import AppKit
import ModelForgeKit

/// How a problem is drawn under the text that caused it.
///
/// Kept apart from the text view so the part that can actually be wrong — turning a range
/// the compiler produced into one there is text to underline — can be tested without an
/// `NSTextView` to hang it on.
enum DiagnosticDecoration {

    /// AppKit has no wavy underline, so a thick dotted one stands in. It reads as a
    /// squiggle at text sizes and, unlike a plain underline, is not mistaken for a link.
    static let underlineStyle = NSUnderlineStyle.thick.rawValue | NSUnderlineStyle.patternDot.rawValue

    /// The same red and orange the problems list uses for the same severities.
    static func color(for severity: Diagnostic.Severity) -> NSColor {
        switch severity {
        case .error: .systemRed
        case .warning: .systemOrange
        case .note: .secondaryLabelColor
        }
    }

    /// What hovering the underline says. Without it a red line under `Usre` states that
    /// something is wrong and nothing about what.
    static func tooltip(for diagnostic: Diagnostic) -> String {
        ([diagnostic.message] + diagnostic.notes.map { "help: \($0.message)" })
            .joined(separator: "\n")
    }

    /// What to underline for `diagnostic`, in `text`.
    ///
    /// Three things have to be survivable. A range can outrun the text, because the result
    /// in hand was compiled from a slightly older version of it. A diagnostic can be
    /// reported at a token that is not there — a missing `}` — giving a zero-width range.
    /// And such a range sits at the end of a line, where the only character available is
    /// the line break, which has no glyph.
    ///
    /// In the last two cases the mark goes on the whole word before the problem, which is
    /// the token the compiler wanted something after. A whole word rather than the single
    /// character before it for a blunt reason: the underline is a dot pattern, and one
    /// narrow glyph is not wide enough for it to draw a single dot — the mark is applied,
    /// and nothing appears on screen.
    ///
    /// - Returns: `nil` when there is nothing in the text to mark.
    static func range(for diagnostic: Diagnostic, in text: NSString) -> NSRange? {
        let length = text.length
        guard length > 0 else { return nil }

        let start = min(max(0, diagnostic.range.utf16Range.lowerBound), length)
        let end = min(max(0, diagnostic.range.utf16Range.upperBound), length)

        if end > start {
            let candidate = NSRange(location: start, length: end - start)
            if !isAllLineBreaks(text, candidate) { return candidate }
        }
        return wordEnding(at: start, in: text)
    }

    /// The run of non-blank characters that ends at or before `offset`.
    private static func wordEnding(at offset: Int, in text: NSString) -> NSRange? {
        var end = offset
        while end > 0, isBlank(text.character(at: end - 1)) { end -= 1 }
        guard end > 0 else { return nil }

        var start = end
        while start > 0, !isBlank(text.character(at: start - 1)) { start -= 1 }
        return NSRange(location: start, length: end - start)
    }

    /// Line terminators only: these have no glyph, so an underline over them is invisible.
    private static func isAllLineBreaks(_ text: NSString, _ range: NSRange) -> Bool {
        for offset in range.location..<NSMaxRange(range) {
            let unit = text.character(at: offset)
            if unit != 0x0A, unit != 0x0D { return false }
        }
        return true
    }

    private static func isBlank(_ unit: unichar) -> Bool {
        unit == 0x0A || unit == 0x0D || unit == 0x20 || unit == 0x09
    }
}
