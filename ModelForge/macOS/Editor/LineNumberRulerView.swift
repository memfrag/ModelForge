//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import AppKit
import ModelForgeKit

/// The line-number gutter down the left of the editor.
///
/// Driven from TextKit 2's layout fragments. Asking an `NSTextView` built by
/// `scrollableTextView()` for its `layoutManager` — the usual way a ruler like this is
/// written — silently downgrades the whole text view to TextKit 1, so every line position
/// here comes from `textLayoutManager` instead.
///
/// One number per *paragraph*, placed on its first visual line: a line long enough to wrap
/// is still one line of the file, and numbering its continuations would make the gutter
/// disagree with every diagnostic the compiler reports.
final class LineNumberRulerView: NSRulerView {

    private weak var codeView: NSTextView?

    /// Rebuilt when the text changes, so a number can be found for an offset without
    /// counting newlines from the top on every draw.
    private var lineTable = LineTable(utf16: [])

    private var font: NSFont

    init(textView: NSTextView, scrollView: NSScrollView) {
        codeView = textView
        font = LineNumberRulerView.rulerFont(matching: textView.font)
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = Self.thickness(forLineCount: 1, font: font)
        refresh()
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Measurements

    /// The gutter's width, wide enough for the highest number it will have to show.
    ///
    /// A two-digit floor, so a short file does not get a sliver of a gutter and the whole
    /// editor does not shift sideways the moment it reaches line 10.
    static func thickness(forLineCount count: Int, font: NSFont) -> CGFloat {
        let digits = max(2, String(max(1, count)).count)
        let sample = String(repeating: "8", count: digits) as NSString
        let width = sample.size(withAttributes: [.font: font]).width
        return ceil(width) + horizontalPadding * 2
    }

    /// Room either side of the digits: the right-hand gap separates them from the code.
    static let horizontalPadding: CGFloat = 8

    static func rulerFont(matching editorFont: NSFont?) -> NSFont {
        NSFont.monospacedDigitSystemFont(ofSize: (editorFont?.pointSize ?? 13) - 1,
                                         weight: .regular)
    }

    // MARK: Updating

    /// The text changed: renumber, and widen the gutter if the file crossed into another
    /// digit.
    func refresh() {
        guard let codeView else { return }
        font = Self.rulerFont(matching: codeView.font)
        lineTable = LineTable(utf16: Array(codeView.string.utf16))

        let wanted = Self.thickness(forLineCount: lineTable.lineCount, font: font)
        if wanted != ruleThickness { ruleThickness = wanted }
        needsDisplay = true
    }

    /// The caret moved, so a different number is the current one.
    func refreshCurrentLine() {
        needsDisplay = true
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        // Deliberately not calling `super`, which would fill the gutter with the ruler's
        // own background. The editor's pane background shows through instead.
        drawHashMarksAndLabels(in: dirtyRect)
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let codeView,
              let layoutManager = codeView.textLayoutManager,
              let contentManager = layoutManager.textContentManager else { return }

        let documentStart = contentManager.documentRange.location
        let inset = codeView.textContainerInset.height
        let visible = codeView.visibleRect
        // Where the text view's origin sits in the ruler's own coordinates.
        let origin = convert(NSPoint.zero, from: codeView).y

        let currentLine = lineTable.line(containing: codeView.selectedRange().location)

        let plain: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: NSColor.tertiaryLabelColor
        ]
        let current: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: NSColor.secondaryLabelColor
        ]

        layoutManager.enumerateTextLayoutFragments(
            from: documentStart,
            options: [.ensuresLayout, .ensuresExtraLineFragment]
        ) { fragment in
            let frame = fragment.layoutFragmentFrame

            // Above the viewport: keep going. Below it: there is nothing left to draw.
            if frame.maxY + inset < visible.minY { return true }
            if frame.minY + inset > visible.maxY { return false }

            let offset = contentManager.offset(from: documentStart,
                                               to: fragment.rangeInElement.location)
            let line = lineTable.line(containing: offset)

            // The first visual line only — the rest are wraps of the same line of the file.
            guard let first = fragment.textLineFragments.first else { return true }

            let label = "\(line)" as NSString
            let attributes = line == currentLine ? current : plain
            let size = label.size(withAttributes: attributes)
            let y = origin + frame.minY + inset + first.typographicBounds.minY
                + (first.typographicBounds.height - size.height) / 2

            label.draw(at: NSPoint(x: ruleThickness - Self.horizontalPadding - size.width,
                                   y: y),
                       withAttributes: attributes)
            return true
        }
    }
}
