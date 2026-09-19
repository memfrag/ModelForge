//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Testing
import Foundation
import ModelForgeKit
@testable import ModelForge

/// What happens when a project is re-read under an open window — a git branch switch, or a
/// Reload after an external change.
///
/// SwiftUI calls `apply(snapshot:previous:)` on the document directly, so this is the one
/// path into a document that nothing in the window initiates. Both of the rules it enforces
/// were written after the corresponding bug.
@Suite("Reloading a project")
@MainActor struct ProjectDocumentApplyTests {

    @Test("A file whose name survives keeps its id, so the selection and its undo stack do too")
    func idsSurviveAReload() async throws {
        let document = makeDocument([("user.model", "model User {}"),
                                     ("account.model", "model Account {}")])
        let before = Dictionary(uniqueKeysWithValues: document.sources.map { ($0.name, $0.id) })

        try await document.apply(snapshot: makeSnapshot([
            ("user.model", "model User { id: UUID }"),
            ("account.model", "model Account {}")
        ]), previous: nil)

        let after = Dictionary(uniqueKeysWithValues: document.sources.map { ($0.name, $0.id) })
        #expect(after == before)
        #expect(document.sources.first { $0.name == "user.model" }?.text == "model User { id: UUID }")
    }

    @Test("A file that appeared on disk gets an id of its own")
    func newFilesGetFreshIDs() async throws {
        let document = makeDocument([("user.model", "")])
        let existing = document.sources[0].id

        try await document.apply(snapshot: makeSnapshot([
            ("user.model", ""),
            ("account.model", "")
        ]), previous: nil)

        let ids = document.sources.map(\.id)
        #expect(ids.count == 2)
        #expect(Set(ids).count == 2)
        #expect(ids.contains(existing))
    }

    @Test("An id freed by a deleted file is not handed to a later one")
    func idsAreNotRecycled() async throws {
        let document = makeDocument([("a.model", ""), ("b.model", "")])
        let originals = Set(document.sources.map(\.id))

        // b disappears…
        try await document.apply(snapshot: makeSnapshot([("a.model", "")]), previous: nil)
        // …and something else shows up in its place.
        try await document.apply(snapshot: makeSnapshot([("a.model", ""), ("c.model", "")]),
                                 previous: nil)

        let cID = try #require(document.sources.first { $0.name == "c.model" }?.id)
        #expect(!originals.contains(cID))
    }

    @Test("Files come back sorted, whatever order they were read in")
    func sourcesAreSortedAfterApply() async throws {
        let document = makeDocument()
        try await document.apply(snapshot: makeSnapshot([
            ("zebra.model", ""), ("alpha.model", ""), ("middle.model", "")
        ]), previous: nil)
        #expect(document.sources.map(\.name) == ["alpha.model", "middle.model", "zebra.model"])
    }

    @Test("An absent manifest means no record of what was generated, not a record of nothing")
    func absentManifestDoesNotClobber() async throws {
        let document = makeDocument([("a.model", "")])
        document.manifest = GenerationManifest(swiftFiles: ["../ios/A.swift"],
                                               kotlinFiles: ["../android/A.kt"])

        // A reload from a bundle whose Manifest.json has not been saved yet. Adopting its
        // empty manifest would orphan the two files already written.
        try await document.apply(snapshot: makeSnapshot([("a.model", "")]), previous: nil)

        #expect(document.manifest.swiftFiles == ["../ios/A.swift"])
        #expect(document.manifest.kotlinFiles == ["../android/A.kt"])
    }

    @Test("A manifest that is present on disk does replace the one in memory")
    func presentManifestIsAdopted() async throws {
        let document = makeDocument([("a.model", "")])
        document.manifest = GenerationManifest(swiftFiles: ["../ios/Old.swift"])

        try await document.apply(
            snapshot: makeSnapshot([("a.model", "")],
                                   manifest: GenerationManifest(swiftFiles: ["../ios/New.swift"])),
            previous: nil)

        #expect(document.manifest.swiftFiles == ["../ios/New.swift"])
    }

    @Test("Settings and load warnings are adopted from what was read")
    func configurationAndWarningsAreAdopted() async throws {
        let document = makeDocument([("a.model", "")])
        var configuration = ProjectConfiguration.default
        configuration.kotlin.package = "com.example.reloaded"

        var snapshot = makeSnapshot([("a.model", "")], configuration: configuration)
        snapshot.warnings = ["bad.model is not valid UTF-8 and was not opened."]

        try await document.apply(snapshot: snapshot, previous: nil)

        #expect(document.configuration.kotlin.package == "com.example.reloaded")
        #expect(document.loadWarnings.count == 1)
    }

    @Test("Saving writes back exactly what the document holds")
    func snapshotMirrorsTheDocument() async throws {
        let document = makeDocument([("user.model", Sample.user)])
        document.configuration.swift.module = "AppModels"
        document.manifest = GenerationManifest(kotlinFiles: ["../android/User.kt"])

        let snapshot = try await document.snapshot(contentType: .modelForgeProject)

        #expect(snapshot.sources.map(\.name) == ["user.model"])
        #expect(snapshot.configuration.swift.module == "AppModels")
        #expect(snapshot.manifest.kotlinFiles == ["../android/User.kt"])
    }

    @Test("Edit, save, reload: the project comes back as it was")
    func editSaveReload() async throws {
        let document = makeDocument([("user.model", Sample.user)])
        document.appendSource(named: "account.model", text: Sample.account)
        document.configuration.kotlin.package = "com.example.app"

        let saved = try await document.snapshot(contentType: .modelForgeProject)
        let onDisk = try ProjectSnapshot(wrapper: try saved.fileWrapper())
        try await document.apply(snapshot: onDisk, previous: saved)

        #expect(document.sources.map(\.name) == ["account.model", "user.model"])
        #expect(document.sources.map(\.text) == [Sample.account, Sample.user])
        #expect(document.configuration.kotlin.package == "com.example.app")
    }
}
