//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Testing
import Foundation
import ModelForgeKit
@testable import ModelForge

/// Format Model Files, as the Edit menu drives it.
@Suite("Formatting a project")
@MainActor struct ProjectFormattingTests {

    @Test("The menu item is offered only when something is actually out of shape")
    func unformattedFilesAreDetected() {
        #expect(makeSession([("a.model", Sample.messy)]).hasUnformattedFiles)
        #expect(!makeSession([("a.model", Sample.user)]).hasUnformattedFiles)
        #expect(!makeSession().hasUnformattedFiles)
    }

    @Test("A file the formatter refuses is not something to offer formatting for")
    func unparseableFilesAreNotOffered() {
        // Otherwise the menu item stays enabled for as long as the syntax error lasts, and
        // choosing it does nothing.
        #expect(!makeSession([("broken.model", Sample.unparseable)]).hasUnformattedFiles)
        #expect(!makeSession([("broken.model", Sample.unparseable),
                              ("tidy.model", Sample.user)]).hasUnformattedFiles)
        #expect(makeSession([("broken.model", Sample.unparseable),
                             ("messy.model", Sample.messy)]).hasUnformattedFiles)
    }

    @Test("What is offered is exactly what formatting will change")
    func theOfferMatchesTheWork() {
        let session = makeSession([("broken.model", Sample.unparseable),
                                   ("messy.model", Sample.messy)])
        #expect(session.hasUnformattedFiles)
        #expect(session.formatAllFiles() == 1)
        #expect(!session.hasUnformattedFiles)
    }

    @Test("Formatting rewrites what needs it and reports how many files changed")
    func formattingRewritesFiles() {
        let session = makeSession([("messy.model", Sample.messy), ("tidy.model", Sample.user)])

        #expect(session.formatAllFiles() == 1)
        #expect(!session.hasUnformattedFiles)
        #expect(session.sources.first { $0.name == "tidy.model" }?.text == Sample.user)
        #expect(session.sources.first { $0.name == "messy.model" }?.text.contains("model Messy {") == true)
    }

    @Test("Formatting an already-tidy project changes nothing and marks nothing")
    func formattingIsIdempotent() {
        let session = makeSession([("a.model", Sample.user)])
        #expect(session.formatAllFiles() == 0)
        #expect(!session.hasLocalEdits)
    }

    @Test("Formatting twice is the same as formatting once")
    func formattingTwiceIsStable() {
        let session = makeSession([("a.model", Sample.messy)])
        #expect(session.formatAllFiles() == 1)
        let once = session.sources[0].text
        #expect(session.formatAllFiles() == 0)
        #expect(session.sources[0].text == once)
    }

    @Test("A file that does not parse is left alone, and does not stop the others")
    func brokenFilesAreLeftAlone() {
        // Rewriting source from a guess at what was meant is how a formatter destroys work.
        let session = makeSession([("broken.model", Sample.unparseable),
                                   ("messy.model", Sample.messy)])

        #expect(session.formatAllFiles() == 1)
        #expect(session.sources.first { $0.name == "broken.model" }?.text == Sample.unparseable)
        #expect(session.sources.first { $0.name == "messy.model" }?.text != Sample.messy)
    }

    @Test("A file with a semantic error is still formatted — only bad syntax is refused")
    func semanticErrorsDoNotBlockFormatting() {
        let session = makeSession([("a.model", "model Broken{\n  owner:NoSuchType\n}\n")])
        #expect(session.formatAllFiles() == 1)
        #expect(session.sources[0].text.contains("model Broken {"))
    }

    @Test("Formatting counts as an unsaved edit")
    func formattingMarksTheProjectEdited() {
        let session = makeSession([("a.model", Sample.messy)])
        #expect(!session.hasLocalEdits)
        session.formatAllFiles()
        #expect(session.hasLocalEdits)
    }
}
