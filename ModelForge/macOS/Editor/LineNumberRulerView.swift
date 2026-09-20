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

    /// A line the compiler had something to say about.
    struct Marker: Equatable {
        var severity: Diagnostic.Severity
        var message: String
    }

    private weak var codeView: NSTextView?

    /// Rebuilt when the text changes, so a number can be found for an offset without
    /// counting newlines from the top on every draw.
    private var lineTable = LineTable(utf16: [])

    private var font: NSFont

    /// A line count to size the gutter for, when it should be wider than this file needs.
    ///
    /// Swift output is reliably longer than the Kotlin generated from the same schema — an
    /// init, coding keys and a coder against a data class — so one pane is often in three
    /// digits while the other is in two. Left to themselves the two gutters differ by a
    /// character and the code in the two panes does not line up.
    var minimumLineCount = 0 {
        didSet { if minimumLineCount != oldValue { refresh() } }
    }

    /// Whether this gutter leaves room for problem markers.
    ///
    /// Fixed at construction rather than following whether there are any: a gutter that
    /// widened the moment you made a mistake would shift the code sideways underneath you.
    private let showsMarkers: Bool

    /// Problems by line number. The editor's gutter shows these; a preview's does not.
    ///
    /// Not `markers`, which is `NSRulerView`'s own property for the things you drag into
    /// a ruler.
    var problemMarkers: [Int: Marker] = [:] {
        didSet { if problemMarkers != oldValue { needsDisplay = true } }
    }

    init(textView: NSTextView, scrollView: NSScrollView, showsMarkers: Bool = false) {
        codeView = textView
        self.showsMarkers = showsMarkers
        font = LineNumberRulerView.rulerFont(matching: textView.font)
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = Self.thickness(forLineCount: 1, font: font, showsMarkers: showsMarkers)
        refresh()
    }

    /// The worst problem on each line, with something to say about it on hover.
    ///
    /// Keyed by the line the compiler reported, not by an offset into the current text:
    /// the marker is a signpost to a line, and keeping a stale one for the length of a
    /// debounce is far less distracting than having them blink out on every keystroke.
    static func problemMarkers(from diagnostics: [Diagnostic]) -> [Int: Marker] {
        var result: [Int: Marker] = [:]
        var counts: [Int: Int] = [:]

        for diagnostic in diagnostics {
            let line = diagnostic.range.start.line
            counts[line, default: 0] += 1
            if let existing = result[line], existing.severity >= diagnostic.severity { continue }
            result[line] = Marker(severity: diagnostic.severity, message: diagnostic.message)
        }

        for (line, count) in counts where count > 1 {
            result[line]?.message += " (+\(count - 1) more)"
        }
        return result
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
    static func thickness(forLineCount count: Int,
                          font: NSFont,
                          showsMarkers: Bool = false) -> CGFloat {
        let digits = max(2, String(max(1, count)).count)
        let sample = String(repeating: "8", count: digits) as NSString
        let width = sample.size(withAttributes: [.font: font]).width
        return ceil(width) + horizontalPadding * 2 + (showsMarkers ? markerLaneWidth : 0)
    }

    /// Room either side of the digits: the right-hand gap separates them from the code.
    static let horizontalPadding: CGFloat = 8

    /// The strip down the far left where problem markers sit, clear of the digits.
    static let markerLaneWidth: CGFloat = 12
    static let markerDiameter: CGFloat = 6

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

        let wanted = Self.thickness(forLineCount: max(lineTable.lineCount, minimumLineCount),
                                    font: font,
                                    showsMarkers: showsMarkers)
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

    /// Tooltip rectangles move with every scroll, so they are rebuilt on each draw.
    private func registerToolTip(_ message: String, for rect: NSRect) {
        addToolTip(rect, owner: message as NSString, userData: nil)
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        removeAllToolTips()
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
            let top = origin + frame.minY + inset + first.typographicBounds.minY
            let y = top + (first.typographicBounds.height - size.height) / 2

            label.draw(at: NSPoint(x: ruleThickness - Self.horizontalPadding - size.width,
                                   y: y),
                       withAttributes: attributes)

            if let marker = problemMarkers[line] {
                let diameter = Self.markerDiameter
                let dot = NSRect(x: (Self.markerLaneWidth - diameter) / 2,
                                 y: top + (first.typographicBounds.height - diameter) / 2,
                                 width: diameter,
                                 height: diameter)
                DiagnosticDecoration.color(for: marker.severity).setFill()
                NSBezierPath(ovalIn: dot).fill()
                registerToolTip(marker.message,
                                for: NSRect(x: 0, y: top,
                                            width: ruleThickness,
                                            height: first.typographicBounds.height))
            }
            return true
        }
    }
}
