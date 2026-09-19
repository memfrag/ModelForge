//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Testing
import ModelForgeKit
@testable import ModelForge

/// The preview column's three-way switch.
///
/// It reads from two places that are stored separately on purpose — the language belongs to
/// the window, the layout is a preference — so the mapping between them is worth pinning.
@Suite("Preview choice")
struct PreviewChoiceTests {

    @Test("One language maps to that language's segment")
    func singleLayout() {
        #expect(PreviewChoice(layout: .single, language: .swift) == .swift)
        #expect(PreviewChoice(layout: .single, language: .kotlin) == .kotlin)
    }

    @Test("Showing both wins over whichever language is remembered")
    func bothLayout() {
        #expect(PreviewChoice(layout: .both, language: .swift) == .both)
        #expect(PreviewChoice(layout: .both, language: .kotlin) == .both)
    }

    @Test("Each segment says what to store")
    func whatEachChoiceWritesBack() {
        #expect(PreviewChoice.swift.layout == .single)
        #expect(PreviewChoice.swift.language == .swift)
        #expect(PreviewChoice.kotlin.layout == .single)
        #expect(PreviewChoice.kotlin.language == .kotlin)
        #expect(PreviewChoice.both.layout == .both)
    }

    @Test("Choosing Both leaves the remembered language alone")
    func bothDoesNotDisturbTheLanguage() {
        // So that switching to Both and back lands you on the language you were reading,
        // rather than always on Swift.
        #expect(PreviewChoice.both.language == nil)

        for language in [Language.swift, .kotlin] {
            let choice = PreviewChoice(layout: .both, language: language)
            #expect(choice == .both)
            #expect(PreviewChoice(layout: choice.layout, language: language) == .both)
            // Collapsing back to one pane, with the language untouched.
            #expect(PreviewChoice(layout: .single, language: language).language == language)
        }
    }

    @Test("Every segment has a name, and Swift and Kotlin use the compiler's")
    func names() {
        #expect(PreviewChoice.swift.displayName == Language.swift.displayName)
        #expect(PreviewChoice.kotlin.displayName == Language.kotlin.displayName)
        #expect(PreviewChoice.both.displayName == "Both")
        #expect(PreviewChoice.allCases.count == 3)
    }
}
