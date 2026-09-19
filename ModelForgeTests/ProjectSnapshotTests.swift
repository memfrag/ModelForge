//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Testing
import Foundation
import ModelForgeKit
@testable import ModelForge

@Suite("Project snapshot")
struct ProjectSnapshotTests {

    // MARK: Helpers

    private func bundle(_ entries: [String: Data]) -> FileWrapper {
        FileWrapper(directoryWithFileWrappers: entries.mapValues {
            FileWrapper(regularFileWithContents: $0)
        })
    }

    private func contents(of wrapper: FileWrapper, _ name: String) -> Data? {
        wrapper.fileWrappers?[name]?.regularFileContents
    }

    // MARK: Round trip

    @Test("Everything a project holds survives being written and read back")
    func roundTrip() throws {
        var configuration = ProjectConfiguration.default
        configuration.kotlin.package = "com.example.roundtrip"
        configuration.swift.module = "AppModels"
        let manifest = GenerationManifest(swiftFiles: ["../ios/User.swift"],
                                          kotlinFiles: ["../android/User.kt"])

        let original = makeSnapshot([("user.model", Sample.user), ("account.model", Sample.account)],
                                    configuration: configuration,
                                    manifest: manifest)

        let reread = try ProjectSnapshot(wrapper: try original.fileWrapper())

        #expect(reread.sources.map(\.name) == ["account.model", "user.model"])
        #expect(reread.sources.map(\.text).sorted() == [Sample.account, Sample.user].sorted())
        #expect(reread.configuration == configuration)
        #expect(reread.manifest == manifest)
        #expect(reread.warnings.isEmpty)
    }

    @Test("Model files are written verbatim, so a diff shows only what was typed")
    func sourcesAreWrittenVerbatim() throws {
        let text = "model A {\r\n    name: String\n}\n\n"
        let wrapper = try makeSnapshot([("a.model", text)]).fileWrapper()
        #expect(contents(of: wrapper, "a.model") == Data(text.utf8))
    }

    @Test("Ids are assigned in sorted name order, so generated output is stable")
    func idsFollowSortedNames() throws {
        let snapshot = try ProjectSnapshot(wrapper: bundle([
            "zebra.model": Data("model Z {}".utf8),
            "alpha.model": Data("model A {}".utf8)
        ]))
        #expect(snapshot.sources.map(\.name) == ["alpha.model", "zebra.model"])
        #expect(snapshot.sources.map(\.id) == [SourceFileID(0), SourceFileID(1)])
    }

    // MARK: What is and is not a source file

    @Test("Files the bundle owns, and anything not a .model, are not opened as sources")
    func onlySourceFilesAreLoaded() throws {
        let snapshot = try ProjectSnapshot(wrapper: bundle([
            "user.model": Data(Sample.user.utf8),
            "README.md": Data("not a model".utf8),
            ".hidden.model": Data("model H {}".utf8),
            ProjectLayout.manifestFileName: Data("{}".utf8)
        ]))
        #expect(snapshot.sources.map(\.name) == ["user.model"])
    }

    @Test("A model file that is not UTF-8 is reported rather than silently dropped")
    func invalidUTF8IsWarnedAbout() throws {
        let snapshot = try ProjectSnapshot(wrapper: bundle([
            "good.model": Data(Sample.user.utf8),
            "bad.model": Data([0xFF, 0xFE, 0xFF])
        ]))
        #expect(snapshot.sources.map(\.name) == ["good.model"])
        #expect(snapshot.warnings.count == 1)
        #expect(snapshot.warnings[0].contains("bad.model"))
    }

    @Test("A bundle that is not a directory is a read error")
    func aFlatFileIsNotAProject() {
        #expect(throws: (any Error).self) {
            try ProjectSnapshot(wrapper: FileWrapper(regularFileWithContents: Data()))
        }
    }

    // MARK: The manifest

    @Test("An empty manifest is not written, so a fresh bundle has no stray file")
    func emptyManifestIsNotWritten() throws {
        let wrapper = try makeSnapshot([("a.model", "")]).fileWrapper()
        #expect(wrapper.fileWrappers?[ProjectLayout.manifestFileName] == nil)
    }

    @Test("A manifest with entries is written")
    func manifestIsWrittenWhenItHasContent() throws {
        let snapshot = makeSnapshot([("a.model", "")],
                                    manifest: GenerationManifest(swiftFiles: ["A.swift"]))
        let wrapper = try snapshot.fileWrapper()
        #expect(contents(of: wrapper, ProjectLayout.manifestFileName) != nil)
    }

    @Test("A corrupt manifest reads as an empty one rather than failing the open")
    func corruptManifestDoesNotBlockOpening() throws {
        let snapshot = try ProjectSnapshot(wrapper: bundle([
            "a.model": Data("model A {}".utf8),
            ProjectLayout.manifestFileName: Data("not json".utf8)
        ]))
        #expect(snapshot.manifest.isEmpty)
        #expect(snapshot.sources.count == 1)
    }

    // MARK: Configuration

    @Test("A project written by a newer ModelForge is refused, not mangled")
    func newerFormatIsRefused() {
        let config = Data("""
            { "formatVersion": 99, "swift": {}, "kotlin": { "package": "com.example" } }
            """.utf8)

        #expect(throws: ProjectLoadError.self) {
            try ProjectSnapshot(wrapper: bundle([
                "a.model": Data("model A {}".utf8),
                ProjectLayout.configurationFileName: config
            ]))
        }
    }

    @Test("Unreadable settings fall back to defaults and say so")
    func unreadableConfigurationWarns() throws {
        let snapshot = try ProjectSnapshot(wrapper: bundle([
            "a.model": Data("model A {}".utf8),
            ProjectLayout.configurationFileName: Data("{ not json".utf8)
        ]))
        #expect(snapshot.configuration == .default)
        #expect(snapshot.warnings.count == 1)
        #expect(snapshot.sources.count == 1)
    }

    @Test("A setting this version does not understand survives being saved by it")
    func unknownKeysArePreserved() throws {
        let config = Data("""
            {
              "formatVersion": 1,
              "swift": { "accessLevel": "internal" },
              "kotlin": { "package": "com.example.models" },
              "somethingFromTheFuture": { "enabled": true }
            }
            """.utf8)

        let snapshot = try ProjectSnapshot(wrapper: bundle([
            "a.model": Data("model A {}".utf8),
            ProjectLayout.configurationFileName: config
        ]))

        let rewritten = try snapshot.fileWrapper()
        let data = try #require(contents(of: rewritten, ProjectLayout.configurationFileName))
        let json = try JSONDecoder().decode(JSONValue.self, from: data)

        #expect(json.object?["somethingFromTheFuture"] != nil)
    }
}
