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
