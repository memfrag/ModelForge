//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Testing
import SwiftUI
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

/// The binding the toolbar's control is driven by.
///
/// It reads from two places and writes to two places, which is exactly the kind of thing
/// that quietly stops agreeing with itself once a second control uses it.
@Suite("Preview choice binding")
@MainActor struct PreviewChoiceBindingTests {

    private func make() -> (Binding<PreviewChoice>, ProjectSession, AppSettings) {
        let session = makeSession([("a.model", Sample.user)])
        let settings = makeSettings()
        return (PreviewChoice.binding(session: session, settings: settings), session, settings)
    }

    @Test("Reading combines the window's language with the app's layout")
    func reading() {
        let (choice, session, settings) = make()

        session.previewLanguage = .kotlin
        settings.previewLayout = .single
        #expect(choice.wrappedValue == .kotlin)

        settings.previewLayout = .both
        #expect(choice.wrappedValue == .both)
    }

    @Test("Choosing a language collapses to one pane and selects it")
    func choosingALanguage() {
        let (choice, session, settings) = make()
        settings.previewLayout = .both

        choice.wrappedValue = .kotlin

        #expect(settings.previewLayout == .single)
        #expect(session.previewLanguage == .kotlin)
    }

    @Test("Choosing Both leaves the language you were reading alone")
    func choosingBoth() {
        // So that going to Both and back lands you where you were, rather than on Swift.
        let (choice, session, settings) = make()
        session.previewLanguage = .kotlin

        choice.wrappedValue = .both
        #expect(settings.previewLayout == .both)
        #expect(session.previewLanguage == .kotlin)

        choice.wrappedValue = .kotlin
        #expect(session.previewLanguage == .kotlin)
    }

    @Test("A round trip through the control changes nothing")
    func roundTrip() {
        let (choice, _, _) = make()
        for option in PreviewChoice.allCases {
            choice.wrappedValue = option
            #expect(choice.wrappedValue == option)
        }
    }
}
