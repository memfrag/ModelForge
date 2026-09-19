import Testing
import Foundation
@testable import ModelForgeKit

/// The bundle layout is shared between the app, which reads it through a `FileWrapper`,
/// and `modelgen`, which reads it off the filesystem. They have to agree exactly, or a
/// schema would build differently in CI than it does on screen.
@Suite("Project bundle")
struct ProjectBundleTests {

    /// Builds a throwaway project on disk and hands back its URL.
    private func makeProject(
        sources: [String: String] = ["user.model": "model User { id: UUID }"],
        configuration: String? = nil,
        manifest: String? = nil
    ) throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("modelforge-tests-\(UUID().uuidString)")
        let bundle = root.appendingPathComponent("Test.modelforge")
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)

        for (name, text) in sources {
            try text.write(to: bundle.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        if let configuration {
            try configuration.write(to: bundle.appendingPathComponent(ProjectLayout.configurationFileName),
                                    atomically: true, encoding: .utf8)
        }
        if let manifest {
            try manifest.write(to: bundle.appendingPathComponent(ProjectLayout.manifestFileName),
                               atomically: true, encoding: .utf8)
        }
        return bundle
    }

    @Test("reads sources, configuration and manifest")
    func readsAProject() throws {
        let url = try makeProject(
            sources: ["b.model": "model B { id: UUID }", "a.model": "model A { id: UUID }"],
            configuration: #"{"formatVersion":1,"kotlin":{"package":"com.example.app"},"swift":{"output":"../ios"}}"#,
            manifest: #"{"swiftFiles":["../ios/Old.swift"],"kotlinFiles":[]}"#)

        let bundle = try ProjectBundle(contentsOf: url)
        // Sorted, so file ids match what the app assigns for the same project.
        #expect(bundle.sources.map(\.name) == ["a.model", "b.model"])
        #expect(bundle.configuration.kotlin.package == "com.example.app")
        #expect(bundle.manifest.swiftFiles == ["../ios/Old.swift"])
        #expect(bundle.name == "Test")
    }

    @Test("ignores files that are not model sources")
    func ignoresNonSources() throws {
        let url = try makeProject(sources: [
            "user.model": "model User { id: UUID }",
            "README.md": "not a model",
            ".hidden.model": "model Hidden { id: UUID }"
        ])
        #expect(try ProjectBundle(contentsOf: url).sources.map(\.name) == ["user.model"])
    }

    @Test("a project with no Config.json still opens, on defaults")
    func toleratesMissingConfiguration() throws {
        let bundle = try ProjectBundle(contentsOf: try makeProject())
        #expect(bundle.configuration == .default)
        #expect(bundle.manifest.isEmpty)
    }

    @Test("refuses a project written by a newer ModelForge")
    func refusesNewerFormat() throws {
        let url = try makeProject(configuration: #"{"formatVersion":99,"kotlin":{},"swift":{}}"#)
        #expect(throws: ProjectBundle.LoadError.newerFormat(found: 99, supported: 1)) {
            try ProjectBundle(contentsOf: url)
        }
    }

    @Test("refuses something that is not a bundle")
    func refusesNonBundle() throws {
        let url = try makeProject().deletingLastPathComponent()
        #expect(throws: ProjectBundle.LoadError.self) {
            try ProjectBundle(contentsOf: url)
        }
    }

    @Test("finds the only project in a directory")
    func locatesByDirectory() throws {
        let url = try makeProject()
        let found = try ProjectBundle.locate(in: url.deletingLastPathComponent())
        #expect(found.url.lastPathComponent == url.lastPathComponent)
    }

    @Test("output paths resolve against the folder holding the bundle")
    func resolvesOutputPaths() throws {
        let url = try makeProject(
            configuration: #"{"formatVersion":1,"kotlin":{"output":"android/models"},"swift":{"output":"../ios/Gen"}}"#)
        let bundle = try ProjectBundle(contentsOf: url)
        #expect(bundle.kotlinOutputDirectory?.path.hasSuffix("android/models") == true)
        #expect(bundle.swiftOutputDirectory?.path.contains("ios/Gen") == true)
    }

    // MARK: Verifying generated output

    @Test("reports exactly what a build would change")
    func reportsPendingChanges() throws {
        let url = try makeProject()
        let bundle = try ProjectBundle(contentsOf: url)
        let output = bundle.generate(bundle.compile())
        let swiftDirectory = bundle.directory.appendingPathComponent("ios")

        let request = GeneratedFileWriter.Request(
            files: output.files,
            previousManifest: GenerationManifest(),
            swiftDirectory: swiftDirectory,
            kotlinDirectory: nil,
            projectDirectory: bundle.directory)

        // Nothing written yet, so everything is pending as a create.
        let before = GeneratedFileWriter.pendingChanges(request)
        #expect(before.allSatisfy { $0.hasPrefix("create ") })
        #expect(before.count == output.files(for: .swift).count)

        _ = try GeneratedFileWriter.write(request)

        // Deterministic output means a second run has nothing to do — which is what makes
        // `modelgen build --verify` usable as a CI gate.
        #expect(GeneratedFileWriter.pendingChanges(request).isEmpty)
    }

    @Test("a file the previous run wrote and this one does not is pending removal")
    func reportsStaleFiles() throws {
        let url = try makeProject()
        let bundle = try ProjectBundle(contentsOf: url)
        let swiftDirectory = bundle.directory.appendingPathComponent("ios")
        try FileManager.default.createDirectory(at: swiftDirectory, withIntermediateDirectories: true)
        let stale = swiftDirectory.appendingPathComponent("Gone.swift")
        try "// stale".write(to: stale, atomically: true, encoding: .utf8)

        let request = GeneratedFileWriter.Request(
            files: [],
            previousManifest: GenerationManifest(swiftFiles: ["ios/Gone.swift"]),
            swiftDirectory: swiftDirectory,
            kotlinDirectory: nil,
            projectDirectory: bundle.directory)

        #expect(GeneratedFileWriter.pendingChanges(request) == ["remove ios/Gone.swift"])
        #expect(try GeneratedFileWriter.write(request).removed == 1)
        #expect(!FileManager.default.fileExists(atPath: stale.path))
    }
}

@Suite("Project layout")
struct ProjectLayoutTests {

    @Test("A name without the extension gets one")
    func theExtensionIsAdded() {
        #expect(ProjectLayout.named("user") == "user.model")
        #expect(ProjectLayout.named("User") == "User.model")
    }

    @Test("A name that already carries the extension keeps it, whatever its case")
    func theExtensionIsNotDoubled() {
        // `User.Model` is the file `user.model` on the filesystems this runs on, so
        // appending another extension would quietly create a second file.
        #expect(ProjectLayout.named("user.model") == "user.model")
        #expect(ProjectLayout.named("User.Model") == "User.Model")
        #expect(ProjectLayout.named("USER.MODEL") == "USER.MODEL")
    }

    @Test("A name that merely contains the extension still gets one")
    func aMisleadingNameStillGetsTheExtension() {
        #expect(ProjectLayout.named("model") == "model.model")
        #expect(ProjectLayout.named("my.model.backup") == "my.model.backup.model")
    }

    @Test("Only visible .model files are sources")
    func whatCountsAsASourceFile() {
        #expect(ProjectLayout.isSourceFile("user.model"))
        #expect(!ProjectLayout.isSourceFile("README.md"))
        #expect(!ProjectLayout.isSourceFile(".hidden.model"))
        #expect(!ProjectLayout.isSourceFile(ProjectLayout.configurationFileName))
    }
}
