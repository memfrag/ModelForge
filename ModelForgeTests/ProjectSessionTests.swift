//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Testing
import Foundation
import ModelForgeKit
@testable import ModelForge

@Suite("Project session")
@MainActor struct ProjectSessionTests {

    // MARK: Compiling

    @Test("Editing a file eventually produces a compiled result and both previews")
    func editingCompiles() async throws {
        let session = makeSession([("user.model", "")])
        let id = session.sources[0].id

        session.updateText(Sample.user, for: id)
        session.sourcesChanged()

        #expect(await waitForType("User", in: session))
        #expect(session.previewFile(for: .swift)?.contents.contains("struct User") == true)
        #expect(session.previewFile(for: .kotlin)?.contents.contains("class User") == true)
    }

    @Test("A slow earlier compile cannot overwrite the result of a later edit")
    func theLatestEditWins() async throws {
        let session = makeSession([("user.model", "")], debounce: 5)
        let id = session.sources[0].id

        for name in ["Alpha", "Beta", "Gamma", "Delta"] {
            session.updateText("model \(name) {}", for: id)
            session.sourcesChanged()
        }

        #expect(await waitForType("Delta", in: session))
        #expect(session.knownTypeNames == ["Delta"])
    }

    @Test("A result stays on screen while the next compile runs, so previews never blank")
    func theLastResultIsKept() async throws {
        let session = makeSession([("user.model", Sample.user)], debounce: 200)
        session.compileNow()
        #expect(await waitForType("User", in: session))

        session.updateText("model Replaced {}", for: session.sources[0].id)
        session.sourcesChanged()

        // The debounce has not elapsed, so the old result is still what the previews draw.
        #expect(session.knownTypeNames == ["User"])
        #expect(await waitForType("Replaced", in: session))
    }

    @Test("Changing settings recompiles at once, without waiting out the debounce")
    func configurationChangesAreNotDebounced() async throws {
        let session = makeSession([("user.model", Sample.user)], debounce: 10_000)
        session.updateConfiguration { $0.kotlin.package = "com.example.immediate" }
        session.configurationChanged()

        #expect(await waitForType("User", in: session))
        #expect(session.previewFile(for: .kotlin)?.contents.contains("com.example.immediate") == true)
    }

    @Test("Types across files are indexed together, sorted, each pointing at its own file")
    func declaredTypesAreIndexed() async throws {
        let session = makeSession([("user.model", Sample.user), ("account.model", Sample.account)])
        session.compileNow()
        #expect(await waitForType("Account", in: session))

        let types = session.declaredTypes
        #expect(types.map(\.name) == ["Account", "User"])
        #expect(types[0].fileName == "account.model")
        #expect(types[1].fileName == "user.model")
        #expect(types[0].location == "account.model:1")
        // The jump target is the declared name, not the whole declaration.
        #expect(types[1].nameOrigin.start.line == 1)
    }

    // MARK: Diagnostics

    @Test("The file you are looking at has its problems listed first")
    func problemsForTheSelectedFileComeFirst() async throws {
        let session = makeSession([("a.model", Sample.broken),
                                   ("b.model", "model AlsoBroken { x: Missing }")])
        session.compileNow()
        #expect(await waitUntil { session.diagnostics.count >= 2 })

        let bID = try #require(session.sources.first { $0.name == "b.model" }?.id)
        session.selection = .file(bID)

        #expect(session.orderedDiagnostics.first?.range.file == bID)
        #expect(session.orderedDiagnostics.count == session.diagnostics.count)
    }

    @Test("A file's badge shows its worst problem, and a clean file has none")
    func badgesReflectEachFile() async throws {
        let session = makeSession([("broken.model", Sample.broken), ("clean.model", Sample.user)])
        session.compileNow()
        #expect(await waitUntil { session.hasErrors })

        let broken = try #require(session.sources.first { $0.name == "broken.model" }?.id)
        let clean = try #require(session.sources.first { $0.name == "clean.model" }?.id)

        #expect(session.worstSeverity(for: broken) == .error)
        #expect(session.worstSeverity(for: clean) == nil)
    }

    @Test("A broken file does not stop the other file's previews rendering")
    func onePreviewSurvivesAnotherFileBreaking() async throws {
        let session = makeSession([("user.model", Sample.user), ("broken.model", Sample.broken)])
        session.compileNow()
        #expect(await waitForType("User", in: session))

        let userID = try #require(session.sources.first { $0.name == "user.model" }?.id)
        session.selection = .file(userID)

        #expect(session.hasErrors)
        #expect(session.previewFile(for: .swift)?.contents.contains("struct User") == true)
        #expect(session.previewFile(for: .kotlin)?.contents.contains("class User") == true)
    }

    // MARK: Navigation

    @Test("Revealing a type declared elsewhere switches files first")
    func revealingSwitchesFiles() async throws {
        let session = makeSession([("user.model", Sample.user), ("account.model", Sample.account)])
        session.compileNow()
        #expect(await waitForType("Account", in: session))

        let userID = try #require(session.sources.first { $0.name == "user.model" }?.id)
        session.selection = .file(userID)

        let account = try #require(session.declaredTypes.first { $0.name == "Account" })
        session.reveal(account)

        #expect(session.selection == .file(account.file))
        #expect(session.pendingSelection == account.nameOrigin)
    }

    @Test("Revealing something in the file already open does not re-select the file")
    func revealingInPlace() async throws {
        let session = makeSession([("user.model", Sample.user)])
        session.compileNow()
        #expect(await waitForType("User", in: session))

        let user = try #require(session.declaredTypes.first)
        let before = session.selection
        session.reveal(user)

        #expect(session.selection == before)
        #expect(session.pendingSelection == user.nameOrigin)
    }

    @Test("Revealing something in a file that has since been deleted does nothing")
    func revealingAGhostIsHarmless() async throws {
        let session = makeSession([("user.model", Sample.user), ("account.model", Sample.account)])
        session.compileNow()
        #expect(await waitForType("Account", in: session))

        let account = try #require(session.declaredTypes.first { $0.name == "Account" })
        session.delete(account.file)
        session.pendingSelection = nil
        session.reveal(account)

        #expect(session.pendingSelection == nil)
    }

    // MARK: Selection

    @Test("Deleting the file you are looking at moves you to another one")
    func deletingTheSelectedFile() {
        let session = makeSession([("a.model", ""), ("b.model", "")])
        let bID = session.sources[1].id
        session.selection = .file(bID)

        session.delete(bID)

        #expect(session.selection == .file(session.sources[0].id))
    }

    @Test("Deleting the last file falls back to the settings form")
    func deletingTheLastFile() {
        let session = makeSession([("a.model", "")])
        session.delete(session.sources[0].id)
        #expect(session.selection == .settings)
    }

    @Test("A selection pointing at a file that vanished from disk is repaired")
    func reloadRepairsTheSelection() {
        let session = makeSession([("a.model", ""), ("b.model", "")])
        let bID = session.sources[1].id
        session.selection = .file(bID)

        // The document changed behind the session's back, as a reload does.
        session.document.removeSource(bID)
        session.sourcesChanged()

        #expect(session.selection == .file(session.sources[0].id))
    }

    @Test("An empty project selects its first file as soon as one appears")
    func theFirstFileGetsSelected() {
        let session = makeSession()
        #expect(session.selection == .settings)

        session.document.appendSource(named: "a.model", text: "")
        session.sourcesChanged()

        #expect(session.selection == .file(session.sources[0].id))
    }

    @Test("Someone who chose the settings form is not pulled out of it")
    func settingsSelectionIsRespected() {
        let session = makeSession([("a.model", "")])
        session.selection = .settings

        session.document.appendSource(named: "b.model", text: "")
        session.sourcesChanged()

        #expect(session.selection == .settings)
    }

    @Test("Adding a file selects it")
    func addingAFileSelectsIt() throws {
        let session = makeSession([("a.model", "")])
        session.addFile()

        let added = try #require(session.sources.first { $0.name == "Untitled.model" })
        #expect(session.selection == .file(added.id))
    }

    // MARK: Renaming

    @Test("An extension is added if you leave it off")
    func renameAddsTheExtension() {
        let session = makeSession([("a.model", "")])
        #expect(session.rename(session.sources[0].id, to: "renamed") == nil)
        #expect(session.sources[0].name == "renamed.model")
    }

    @Test("An extension you typed is not doubled")
    func renameKeepsAnExtensionYouTyped() {
        let session = makeSession([("a.model", "")])
        #expect(session.rename(session.sources[0].id, to: "renamed.model") == nil)
        #expect(session.sources[0].name == "renamed.model")
    }

    @Test("An empty name is refused with a reason")
    func renameRefusesAnEmptyName() {
        let session = makeSession([("a.model", "")])
        #expect(session.rename(session.sources[0].id, to: "   ") == "The name cannot be empty.")
        #expect(session.sources[0].name == "a.model")
    }

    @Test("A name already in use is refused with a reason")
    func renameRefusesADuplicate() {
        let session = makeSession([("a.model", ""), ("b.model", "")])
        let message = session.rename(session.sources[0].id, to: "b")
        #expect(message?.contains("b.model") == true)
        #expect(session.sources.map(\.name) == ["a.model", "b.model"])
    }

    // MARK: Unsaved edits

    @Test("Typing marks the project as holding unsaved edits")
    func typingMarksTheProjectEdited() {
        let session = makeSession([("a.model", "")])
        #expect(!session.hasLocalEdits)

        session.updateText("model A {}", for: session.sources[0].id)
        #expect(session.hasLocalEdits)
    }

    @Test("Re-typing exactly what is already there does not mark the project edited")
    func anIdenticalEditIsNotAnEdit() {
        let session = makeSession([("a.model", "model A {}")])
        session.updateText("model A {}", for: session.sources[0].id)
        #expect(!session.hasLocalEdits)
    }

    @Test("File operations and settings changes count as unsaved edits")
    func otherMutationsMarkTheProjectEdited() {
        for mutate in [
            { (session: ProjectSession) in session.addFile() },
            { session in _ = session.rename(session.sources[0].id, to: "renamed") },
            { session in session.delete(session.sources[0].id) },
            { session in session.updateConfiguration { $0.kotlin.package = "com.example.x" } }
        ] {
            let session = makeSession([("a.model", "")])
            mutate(session)
            #expect(session.hasLocalEdits)
        }
    }

    @Test("Setting a value to what it already is does not mark the project edited")
    func anIdenticalConfigurationChangeIsNotAnEdit() {
        let session = makeSession([("a.model", "")])
        session.updateConfiguration { $0.kotlin.package = session.configuration.kotlin.package }
        #expect(!session.hasLocalEdits)
    }

    @Test("Recording what was generated is not a user edit")
    func writingTheManifestIsNotAnEdit() {
        // Generate writes the manifest back into the document. Treating that as an edit is
        // what made the file watcher start prompting instead of reloading.
        let session = makeSession([("a.model", "")])
        session.document.manifest = GenerationManifest(swiftFiles: ["../ios/A.swift"])
        #expect(!session.hasLocalEdits)
    }

    // MARK: Generating

    @Test("A project that has never been saved cannot generate, and says why")
    func anUnsavedProjectCannotGenerate() {
        // Output paths resolve against the bundle's own directory, so there is nowhere to
        // write until the project has one.
        let session = makeSession([("a.model", Sample.user)])
        #expect(session.fileURL == nil)
        #expect(!session.canGenerate)
        #expect(session.generationBlocker == "Save the project first")
    }

    // MARK: Undo

    @Test("Each file gets its own undo history, and the same one each time")
    func undoManagersArePerFile() {
        let session = makeSession([("a.model", ""), ("b.model", "")])
        let a = session.undoManager(for: session.sources[0].id)
        let b = session.undoManager(for: session.sources[1].id)

        #expect(a !== b)
        #expect(session.undoManager(for: session.sources[0].id) === a)
    }

    @Test("A deleted file's undo history goes with it")
    func undoHistoryIsDiscardedWithTheFile() {
        let session = makeSession([("a.model", ""), ("b.model", "")])
        let id = session.sources[0].id
        let original = session.undoManager(for: id)

        session.delete(id)

        #expect(session.undoManager(for: id) !== original)
    }
}
