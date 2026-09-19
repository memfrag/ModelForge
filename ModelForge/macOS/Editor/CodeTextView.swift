//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI
import AppKit
import ModelForgeKit

/// Shared setup for every code view in the app.
///
/// `NSTextView` rather than SwiftUI's `TextEditor` because on macOS `TextEditor` applies
/// automatic quote and dash substitution — curly quotes, em dashes — which silently
/// corrupts source code, and there is no way to turn it off from SwiftUI.
enum CodeTextViewFactory {

    static func font(size: Double) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    static func makeScrollView(editable: Bool, fontSize: Double) -> (NSScrollView, NSTextView) {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        // swiftlint:disable:next force_cast
        let textView = scrollView.documentView as! NSTextView

        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isRichText = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true

        textView.isEditable = editable
        textView.isSelectable = true
        textView.allowsUndo = editable
        textView.font = font(size: fontSize)
        textView.textContainerInset = NSSize(width: 8, height: 12)
        textView.drawsBackground = false

        return (scrollView, textView)
    }
}

// MARK: - Editable source editor

/// The DSL editor.
struct SourceEditorView: NSViewRepresentable {

    let source: ProjectSource
    let session: ProjectSession
    /// This file's problems, underlined in place.
    let diagnostics: [Diagnostic]
    /// The version of this file the compiler produced `diagnostics` from.
    ///
    /// Carried alongside them because a range only means anything against the text it was
    /// measured in, and while you are typing the result on hand describes the version
    /// before your last keystroke.
    let diagnosedText: String?
    let theme: EditorTheme
    let fontSize: Double

    func makeNSView(context: Context) -> NSScrollView {
        let (scrollView, textView) = CodeTextViewFactory.makeScrollView(editable: true,
                                                                        fontSize: fontSize)
        textView.delegate = context.coordinator
        context.coordinator.textView = textView

        // Installed before `string` is set below so the initial contents are highlighted
        // on the same pass as every later edit.
        textView.textStorage?.delegate = context.coordinator
        context.coordinator.adopt(source, in: textView)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView else { return }

        if textView.font?.pointSize != CGFloat(fontSize) {
            textView.font = CodeTextViewFactory.font(size: fontSize)
            context.coordinator.rehighlightEverything()
        }

        // Switching files swaps the text and the undo history together.
        if context.coordinator.sourceID != source.id {
            context.coordinator.adopt(source, in: textView)
        } else if textView.string != source.text {
            // An external change, or an undo driven from elsewhere. Keep the caret where
            // it was rather than snapping it to the start.
            let selected = textView.selectedRange()
            textView.string = source.text
            let location = min(selected.location, (source.text as NSString).length)
            textView.setSelectedRange(NSRange(location: location, length: 0))
        }

        context.coordinator.applyDiagnostics(in: textView)

        if let range = session.pendingSelection {
            context.coordinator.select(range, in: textView)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate {

        var parent: SourceEditorView
        private(set) var sourceID: SourceFileID?
        private var fileName = ""
        weak var textView: NSTextView?

        private nonisolated(unsafe) var themeObserver: (any NSObjectProtocol)?
        /// Suppresses the change notification while we are the ones replacing the text.
        private var isAdopting = false

        /// What is currently underlined, so an update that changes neither the problems
        /// nor the text does no work.
        private var markedDiagnostics: [Diagnostic]?
        private var markedText: String?

        init(_ parent: SourceEditorView) {
            self.parent = parent
            super.init()
            themeObserver = NotificationCenter.default.addObserver(
                forName: .editorThemeChanged, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.rehighlightEverything() }
            }
        }

        deinit {
            if let themeObserver {
                NotificationCenter.default.removeObserver(themeObserver)
            }
        }

        /// Point the text view at a different file, bringing that file's undo history with
        /// it so ⌘Z means what it did the last time this file was on screen.
        func adopt(_ source: ProjectSource, in textView: NSTextView) {
            sourceID = source.id
            fileName = source.name
            isAdopting = true
            textView.string = source.text
            isAdopting = false
            textView.setSelectedRange(NSRange(location: 0, length: 0))
            rehighlightEverything()
        }

        /// The per-file undo manager. `NSTextView` asks its delegate for this, which is
        /// what makes the text view's own coalescing work against our stack.
        func undoManager(for view: NSTextView) -> UndoManager? {
            sourceID.map { parent.session.undoManager(for: $0) }
        }

        func select(_ range: SourceRange, in textView: NSTextView) {
            let length = (textView.string as NSString).length
            let start = min(range.utf16Range.lowerBound, length)
            let end = min(range.utf16Range.upperBound, length)
            let nsRange = NSRange(location: start, length: max(0, end - start))

            textView.setSelectedRange(nsRange)
            textView.scrollRangeToVisible(nsRange)
            textView.window?.makeFirstResponder(textView)
            parent.session.pendingSelection = nil
        }

        // MARK: Highlighting

        func textStorage(_ textStorage: NSTextStorage,
                         didProcessEditing editedMask: NSTextStorageEditActions,
                         range editedRange: NSRange,
                         changeInLength delta: Int) {
            guard editedMask.contains(.editedCharacters) else { return }
            guard let sourceID else { return }

            // Re-lex only the paragraphs the edit touched. This is exact rather than an
            // approximation, because no DSL token spans a line.
            let text = textStorage.string as NSString
            let paragraph = text.paragraphRange(for: editedRange)
            highlight(textStorage, range: paragraph, text: text, fileID: sourceID)
        }

        func rehighlightEverything() {
            guard let textView, let storage = textView.textStorage, let sourceID else { return }
            let text = storage.string as NSString
            storage.beginEditing()
            highlight(storage, range: NSRange(location: 0, length: text.length),
                      text: text, fileID: sourceID)
            storage.endEditing()

            // `highlight` replaces every attribute in its range, underlines included.
            markedDiagnostics = nil
            applyDiagnostics(in: textView)
        }

        // MARK: Diagnostics

        /// Underline every problem the compiler found in this file.
        ///
        /// Applied as text-storage attributes, never as layout-manager temporary ones:
        /// `NSTextView.scrollableTextView()` is TextKit 2, and reaching for `layoutManager`
        /// silently downgrades it to TextKit 1.
        ///
        /// Nothing is marked until the compiler has seen the text that is on screen. While
        /// you type, the line you are on loses its underline — the keystroke-tier highlight
        /// clears it along with the colours — and gets it back when the next compile lands.
        /// Marking the stale ranges in between is what would make them crawl as you type.
        func applyDiagnostics(in textView: NSTextView) {
            guard let storage = textView.textStorage else { return }
            guard let diagnosed = parent.diagnosedText, diagnosed == storage.string else { return }

            let diagnostics = parent.diagnostics
            guard markedDiagnostics != diagnostics || markedText != diagnosed else { return }
            markedDiagnostics = diagnostics
            markedText = diagnosed

            let text = storage.string as NSString
            let whole = NSRange(location: 0, length: text.length)

            storage.beginEditing()
            storage.removeAttribute(.underlineStyle, range: whole)
            storage.removeAttribute(.underlineColor, range: whole)
            storage.removeAttribute(.toolTip, range: whole)

            for diagnostic in diagnostics {
                guard let range = DiagnosticDecoration.range(for: diagnostic, in: text) else { continue }
                storage.addAttributes([
                    .underlineStyle: DiagnosticDecoration.underlineStyle,
                    .underlineColor: DiagnosticDecoration.color(for: diagnostic.severity),
                    .toolTip: DiagnosticDecoration.tooltip(for: diagnostic)
                ], range: range)
            }
            storage.endEditing()
        }

        private func highlight(_ storage: NSTextStorage,
                               range: NSRange,
                               text: NSString,
                               fileID: SourceFileID) {
            guard range.length >= 0, NSMaxRange(range) <= text.length else { return }

            let font = CodeTextViewFactory.font(size: parent.fontSize)
            storage.setAttributes([.font: font, .foregroundColor: NSColor.labelColor], range: range)

            let source = SourceFile(id: fileID, name: fileName, text: storage.string)
            let tokens = Lexer.tokenize(source, in: range.location..<NSMaxRange(range))
            let theme = parent.theme

            for span in DSLHighlightClassifier.spans(for: tokens) {
                let spanRange = NSRange(location: span.range.lowerBound,
                                        length: span.range.count)
                guard NSMaxRange(spanRange) <= text.length else { continue }
                storage.addAttribute(.foregroundColor,
                                     value: theme.nsColor(for: span.kind),
                                     range: spanRange)
            }
        }

        // MARK: Editing

        func textDidChange(_ notification: Notification) {
            guard !isAdopting, let textView = notification.object as? NSTextView else { return }
            guard let sourceID else { return }
            parent.session.updateText(textView.string, for: sourceID)
        }
    }
}

// MARK: - Read-only preview

/// A read-only view of generated Swift or Kotlin.
///
/// The same `NSTextView` machinery as the editor rather than a concatenated SwiftUI
/// `Text`: text has to stay selectable so it can be copied, and `Text` concatenation slows
/// down badly past a few hundred runs.
struct GeneratedCodeView: NSViewRepresentable {

    let text: String
    let language: Language
    let knownTypeNames: Set<String>
    let theme: EditorTheme
    let fontSize: Double

    func makeNSView(context: Context) -> NSScrollView {
        let (scrollView, textView) = CodeTextViewFactory.makeScrollView(editable: false,
                                                                        fontSize: fontSize)
        context.coordinator.textView = textView
        context.coordinator.apply(self, to: textView, preservingScroll: false)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.apply(self, to: textView, preservingScroll: true)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator {

        weak var textView: NSTextView?
        private var lastText: String?
        private var lastFontSize: Double?
        private nonisolated(unsafe) var themeObserver: (any NSObjectProtocol)?
        private var pending: GeneratedCodeView?

        init() {
            themeObserver = NotificationCenter.default.addObserver(
                forName: .editorThemeChanged, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, let view = self.pending, let textView = self.textView else { return }
                    self.lastText = nil
                    self.apply(view, to: textView, preservingScroll: true)
                }
            }
        }

        deinit {
            if let themeObserver {
                NotificationCenter.default.removeObserver(themeObserver)
            }
        }

        func apply(_ view: GeneratedCodeView, to textView: NSTextView, preservingScroll: Bool) {
            pending = view
            guard lastText != view.text || lastFontSize != view.fontSize else { return }
            lastText = view.text
            lastFontSize = view.fontSize

            let visible = textView.enclosingScrollView?.contentView.bounds.origin
            textView.textStorage?.setAttributedString(attributedString(for: view))

            if preservingScroll, let visible {
                textView.enclosingScrollView?.contentView.scroll(to: visible)
                textView.enclosingScrollView?.reflectScrolledClipView(
                    textView.enclosingScrollView!.contentView)
            }
        }

        private func attributedString(for view: GeneratedCodeView) -> NSAttributedString {
            let font = CodeTextViewFactory.font(size: view.fontSize)
            let result = NSMutableAttributedString(
                string: view.text,
                attributes: [.font: font, .foregroundColor: NSColor.labelColor])

            let length = (view.text as NSString).length
            let spans = GeneratedCodeLexer.spans(in: view.text,
                                                 language: view.language,
                                                 knownTypeNames: view.knownTypeNames)
            for span in spans {
                let range = NSRange(location: span.range.lowerBound, length: span.range.count)
                guard NSMaxRange(range) <= length else { continue }
                result.addAttribute(.foregroundColor,
                                    value: view.theme.nsColor(for: span.kind),
                                    range: range)
            }
            return result
        }
    }
}
