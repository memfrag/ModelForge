//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Testing
import AppKit
import SwiftUI
import ModelForgeKit
@testable import ModelForge

/// The editor's underlines, driven through the real coordinator against a real
/// `NSTextStorage`.
///
/// Worth doing rather than trusting screenshots: whether a mark ends up somewhere the user
/// can see depends on the compiler's range, the clamping, and the guard against marking
/// text the compiler has not seen — and a missing underline looks the same on screen
/// whichever of the three dropped it.
@Suite("Editor diagnostics")
@MainActor struct EditorDiagnosticsTests {

    /// One underlined run: where it is, what it says, and what colour it is.
    struct Mark: Equatable {
        var range: NSRange
        var text: String
        var color: NSColor
        var tooltip: String
    }

    /// Compile `text`, run it through the coordinator, and report what got underlined.
    ///
    /// - Parameter onScreen: what the text view holds, when that differs from what was
    ///   compiled — which is the situation mid-keystroke.
    private func marks(in text: String, onScreen: String? = nil) async -> [Mark] {
        let session = makeSession([("a.model", text)])
        session.compileNow()
        _ = await waitUntil { session.result != nil }

        let source = session.sources[0]
        let view = SourceEditorView(source: source,
                                    session: session,
                                    diagnostics: session.diagnostics(for: source.id),
                                    diagnosedText: session.diagnosedText(for: source.id),
                                    theme: EditorTheme(),
                                    fontSize: 13)

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
        textView.string = onScreen ?? text

        let coordinator = SourceEditorView.Coordinator(view)
        coordinator.applyDiagnostics(in: textView)

        guard let storage = textView.textStorage else { return [] }
        let whole = NSRange(location: 0, length: storage.length)
        var found: [Mark] = []
        storage.enumerateAttribute(.underlineStyle, in: whole) { value, range, _ in
            guard value != nil else { return }
            found.append(Mark(
                range: range,
                text: (storage.string as NSString).substring(with: range),
                color: storage.attribute(.underlineColor, at: range.location,
                                         effectiveRange: nil) as? NSColor ?? .clear,
                tooltip: storage.attribute(.toolTip, at: range.location,
                                           effectiveRange: nil) as? String ?? ""))
        }
        return found
    }

    // MARK: What gets marked

    @Test("An unknown type is underlined in red, under the name itself")
    func anUnknownTypeIsMarked() async {
        let found = await marks(in: "model User {}\nmodel A {\n    owner: Usre\n}\n")

        #expect(found.count == 1)
        #expect(found.first?.text == "Usre")
        #expect(found.first?.color == .systemRed)
        #expect(found.first?.tooltip.contains("Usre") == true)
        #expect(found.first?.tooltip.contains("help: ") == true)
    }

    @Test("A warning is underlined in orange")
    func aWarningIsMarked() async {
        let found = await marks(in: "model A {\n    class: String\n}\n")

        #expect(found.count == 1)
        #expect(found.first?.text == "class")
        #expect(found.first?.color == .systemOrange)
    }

    @Test("A missing brace lands on the last thing typed, not on the line break")
    func aMissingBraceIsMarkedSomewhereVisible() async {
        // The compiler reports this just past the final token, where the only character is
        // a newline. Underlining that draws nothing, and the file would badge as broken
        // with no mark in it anywhere.
        let found = await marks(in: "model Unclosed {\n    name: String\n")

        #expect(found.count == 1)
        // Wide enough for the dot pattern to actually draw, which one character is not.
        #expect(found.first?.text == "String")
        #expect(found.first?.color == .systemRed)
    }

    @Test("A clean file has nothing underlined")
    func aCleanFileIsUnmarked() async {
        #expect(await marks(in: Sample.user).isEmpty)
    }

    @Test("Several problems are each marked separately")
    func severalProblems() async {
        let found = await marks(in: "model User {}\nmodel A {\n    owner: Usre\n    class: String\n}\n")

        #expect(found.count == 2)
        #expect(found.map(\.text) == ["Usre", "class"])
        #expect(found.map(\.color) == [.systemRed, .systemOrange])
    }

    // MARK: What does not get marked

    @Test("Nothing is marked on text the compiler has not seen")
    func staleTextIsLeftAlone() async {
        // Mid-keystroke the result in hand describes the previous version of the file.
        // Marking it puts the underline under whatever now happens to sit at that offset.
        let compiled = "model User {}\nmodel A {\n    owner: Usre\n}\n"
        let found = await marks(in: compiled, onScreen: "\n\n" + compiled)

        #expect(found.isEmpty)
    }

    @Test("Nothing is marked before the first compile has finished")
    func nothingBeforeACompile() {
        let session = makeSession([("a.model", "model A {\n    owner: Usre\n}\n")])
        let source = session.sources[0]
        let view = SourceEditorView(source: source,
                                    session: session,
                                    diagnostics: [],
                                    diagnosedText: nil,
                                    theme: EditorTheme(),
                                    fontSize: 13)

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
        textView.string = source.text
        SourceEditorView.Coordinator(view).applyDiagnostics(in: textView)

        let storage = textView.textStorage
        #expect(storage?.attribute(.underlineStyle, at: 0, effectiveRange: nil) == nil)
    }

    @Test("Marking again replaces what was there rather than adding to it")
    func marksAreReplaced() async {
        let session = makeSession([("a.model", "model User {}\nmodel A {\n    owner: Usre\n}\n")])
        session.compileNow()
        _ = await waitUntil { session.result != nil }

        let source = session.sources[0]
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
        textView.string = source.text

        let withProblem = SourceEditorView(source: source, session: session,
                                           diagnostics: session.diagnostics(for: source.id),
                                           diagnosedText: session.diagnosedText(for: source.id),
                                           theme: EditorTheme(), fontSize: 13)
        let coordinator = SourceEditorView.Coordinator(withProblem)
        coordinator.applyDiagnostics(in: textView)

        // The same text, now compiling cleanly — the old underline has to come off.
        coordinator.parent = SourceEditorView(source: source, session: session,
                                              diagnostics: [],
                                              diagnosedText: source.text,
                                              theme: EditorTheme(), fontSize: 13)
        coordinator.applyDiagnostics(in: textView)

        let storage = try? #require(textView.textStorage)
        var any = false
        storage?.enumerateAttribute(.underlineStyle,
                                    in: NSRange(location: 0, length: storage?.length ?? 0)) { value, _, _ in
            if value != nil { any = true }
        }
        #expect(!any)
    }
}
