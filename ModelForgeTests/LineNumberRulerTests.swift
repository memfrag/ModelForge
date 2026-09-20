//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Testing
import AppKit
import ModelForgeKit
@testable import ModelForge

/// The gutter's width.
///
/// Drawing is AppKit's and is checked by looking at it; what is worth pinning here is the
/// width, because it is what makes the editor shift sideways — the one way a line-number
/// ruler can be actively annoying rather than merely wrong.
@Suite("Line number ruler")
@MainActor struct LineNumberRulerTests {

    private var font: NSFont { LineNumberRulerView.rulerFont(matching: nil) }

    // MARK: Width

    @Test("A short file still gets a two-digit gutter")
    func theFloorIsTwoDigits() {
        // Otherwise the whole editor shifts sideways the moment the file reaches line 10.
        let one = LineNumberRulerView.thickness(forLineCount: 1, font: font)
        #expect(one == LineNumberRulerView.thickness(forLineCount: 99, font: font))
    }

    @Test("The gutter widens when the file crosses into another digit")
    func itWidensByDigit() {
        let two = LineNumberRulerView.thickness(forLineCount: 99, font: font)
        let three = LineNumberRulerView.thickness(forLineCount: 100, font: font)
        let four = LineNumberRulerView.thickness(forLineCount: 1000, font: font)

        #expect(two < three)
        #expect(three < four)
    }

    @Test("It does not move for every line added within a digit")
    func itIsStableWithinADigit() {
        let widths = Set((100...999).map {
            LineNumberRulerView.thickness(forLineCount: $0, font: font)
        })
        #expect(widths.count == 1)
    }

    @Test("A file of no lines is treated as a file of one")
    func zeroAndNegativeCounts() {
        let one = LineNumberRulerView.thickness(forLineCount: 1, font: font)
        #expect(LineNumberRulerView.thickness(forLineCount: 0, font: font) == one)
        #expect(LineNumberRulerView.thickness(forLineCount: -5, font: font) == one)
    }

    @Test("A bigger editor font means a bigger gutter")
    func itFollowsTheFont() {
        let small = LineNumberRulerView.rulerFont(matching: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular))
        let large = LineNumberRulerView.rulerFont(matching: NSFont.monospacedSystemFont(ofSize: 20, weight: .regular))

        #expect(small.pointSize < large.pointSize)
        #expect(LineNumberRulerView.thickness(forLineCount: 500, font: small)
                < LineNumberRulerView.thickness(forLineCount: 500, font: large))
    }

    @Test("The digits sit a point below the code, and never scale to nothing")
    func rulerFontSize() {
        let editor = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        #expect(LineNumberRulerView.rulerFont(matching: editor).pointSize == 12)
        #expect(LineNumberRulerView.rulerFont(matching: nil).pointSize == 12)
    }

    // MARK: Against a real text view

    private func makeRuler(text: String) -> (LineNumberRulerView, NSTextView) {
        let (scrollView, textView) = CodeTextViewFactory.makeScrollView(editable: true, fontSize: 13)
        textView.string = text
        let ruler = LineNumberRulerView(textView: textView, scrollView: scrollView)
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        ruler.refresh()
        return (ruler, textView)
    }

    @Test("The gutter sizes itself to the file it is showing")
    func thicknessFollowsTheText() {
        let (short, _) = makeRuler(text: "model A {\n}\n")
        let (long, _) = makeRuler(text: (1...400).map { "// line \($0)" }.joined(separator: "\n"))

        #expect(short.ruleThickness == LineNumberRulerView.thickness(forLineCount: 3, font: font))
        #expect(long.ruleThickness == LineNumberRulerView.thickness(forLineCount: 400, font: font))
        #expect(short.ruleThickness < long.ruleThickness)
    }

    @Test("Growing the file past a digit widens the gutter on the next refresh")
    func thicknessFollowsAnEdit() {
        let (ruler, textView) = makeRuler(text: "model A {\n}\n")
        let before = ruler.ruleThickness

        textView.string = (1...150).map { "// line \($0)" }.joined(separator: "\n")
        ruler.refresh()

        #expect(ruler.ruleThickness > before)
    }

    @Test("The editor is still TextKit 2 with a ruler attached")
    func theTextViewIsNotDowngraded() {
        // Asking an NSTextView for its `layoutManager` — the usual way a ruler like this is
        // written — silently drops it back to TextKit 1. This is the assertion that catches
        // that happening by accident later.
        let (_, textView) = makeRuler(text: "model A {\n}\n")
        #expect(textView.textLayoutManager != nil)
    }
}

@Suite("Gutter problem markers")
@MainActor struct GutterMarkerTests {

    private func diagnostic(line: Int,
                            severity: Diagnostic.Severity,
                            message: String) -> Diagnostic {
        let location = SourceLocation(offset: line * 10, line: line, column: 1)
        return Diagnostic(code: severity == .error ? .unknownType : .reservedName,
                          severity: severity,
                          message: message,
                          range: SourceRange(file: SourceFileID(0), start: location, end: location))
    }

    @Test("Nothing to mark in a clean file")
    func noDiagnostics() {
        #expect(LineNumberRulerView.problemMarkers(from: []).isEmpty)
    }

    @Test("Each problem marks its own line")
    func oneMarkerPerLine() {
        let markers = LineNumberRulerView.problemMarkers(from: [
            diagnostic(line: 7, severity: .error, message: "unknown type 'Usre'"),
            diagnostic(line: 9, severity: .warning, message: "'class' is reserved")
        ])

        #expect(markers.count == 2)
        #expect(markers[7]?.severity == .error)
        #expect(markers[7]?.message == "unknown type 'Usre'")
        #expect(markers[9]?.severity == .warning)
        #expect(markers[3] == nil)
    }

    @Test("A line with both an error and a warning is marked as an error")
    func theWorstSeverityWins() {
        // Whichever order they arrive in — a line is as broken as its worst problem.
        let warningFirst = LineNumberRulerView.problemMarkers(from: [
            diagnostic(line: 4, severity: .warning, message: "reserved"),
            diagnostic(line: 4, severity: .error, message: "unknown type")
        ])
        let errorFirst = LineNumberRulerView.problemMarkers(from: [
            diagnostic(line: 4, severity: .error, message: "unknown type"),
            diagnostic(line: 4, severity: .warning, message: "reserved")
        ])

        #expect(warningFirst[4]?.severity == .error)
        #expect(errorFirst[4]?.severity == .error)
        #expect(warningFirst[4]?.message.hasPrefix("unknown type") == true)
        #expect(errorFirst[4]?.message.hasPrefix("unknown type") == true)
    }

    @Test("A line with several problems says how many, so one message is not the whole story")
    func severalOnOneLine() {
        let markers = LineNumberRulerView.problemMarkers(from: [
            diagnostic(line: 2, severity: .error, message: "first"),
            diagnostic(line: 2, severity: .error, message: "second"),
            diagnostic(line: 2, severity: .error, message: "third")
        ])

        #expect(markers.count == 1)
        #expect(markers[2]?.message.contains("(+2 more)") == true)
    }

    @Test("A single problem is not given a count")
    func oneProblemHasNoCount() {
        let markers = LineNumberRulerView.problemMarkers(from: [
            diagnostic(line: 2, severity: .error, message: "only one")
        ])
        #expect(markers[2]?.message == "only one")
    }

    @Test("The marker lane is reserved whether or not anything is wrong")
    func theLaneIsAlwaysReserved() {
        // A gutter that widened the moment you made a mistake would shift the code
        // sideways underneath you.
        let font = LineNumberRulerView.rulerFont(matching: nil)
        let plain = LineNumberRulerView.thickness(forLineCount: 50, font: font)
        let withLane = LineNumberRulerView.thickness(forLineCount: 50, font: font,
                                                     showsMarkers: true)

        #expect(withLane == plain + LineNumberRulerView.markerLaneWidth)
    }
}

@Suite("Aligning two gutters")
@MainActor struct GutterAlignmentTests {

    private func ruler(lines: Int, alignedWith minimum: Int = 0) -> LineNumberRulerView {
        let (scrollView, textView) = CodeTextViewFactory.makeScrollView(editable: false, fontSize: 13)
        textView.string = (1...max(1, lines)).map { "// line \($0)" }.joined(separator: "\n")
        let ruler = LineNumberRulerView(textView: textView, scrollView: scrollView)
        ruler.minimumLineCount = minimum
        ruler.refresh()
        return ruler
    }

    @Test("Left alone, a longer file gets a wider gutter")
    func differentFilesDiffer() {
        // Swift output is reliably longer than the Kotlin from the same schema. The Sopa
        // widget file is 108 lines against Kotlin's 43 — three digits against two — so the
        // two panes' code starts at different columns.
        #expect(ruler(lines: 108).ruleThickness > ruler(lines: 43).ruleThickness)
    }

    @Test("Given the same count to size for, both gutters match")
    func alignmentMakesThemEqual() {
        let swift = ruler(lines: 108, alignedWith: 108)
        let kotlin = ruler(lines: 43, alignedWith: 108)

        #expect(swift.ruleThickness == kotlin.ruleThickness)
    }

    @Test("A minimum smaller than the file changes nothing")
    func aSmallerMinimumIsIgnored() {
        // The gutter still has to fit its own numbers.
        #expect(ruler(lines: 500, alignedWith: 20).ruleThickness == ruler(lines: 500).ruleThickness)
    }

    @Test("Zero means size for this file alone")
    func zeroMeansUnaligned() {
        #expect(ruler(lines: 43, alignedWith: 0).ruleThickness == ruler(lines: 43).ruleThickness)
    }

    @Test("Changing the alignment afterwards resizes the gutter")
    func changingTheMinimumResizes() {
        let subject = ruler(lines: 43)
        let before = subject.ruleThickness

        subject.minimumLineCount = 1000
        #expect(subject.ruleThickness > before)

        subject.minimumLineCount = 0
        #expect(subject.ruleThickness == before)
    }
}
