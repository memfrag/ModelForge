//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Testing
import Foundation
import ModelForgeKit
@testable import ModelForge

/// What the MCP tools do to a project.
///
/// This is the surface a coding agent drives and no human ever looks at, so it is the one
/// place where a wrong answer goes unnoticed. Every read here compiles synchronously rather
/// than reading whatever the window last produced — the UI's compile is debounced, so a tool
/// called straight after a write would otherwise report the state from before it. Several of
/// the tests below exist to pin exactly that.
@Suite("MCP model service")
@MainActor struct MCPModelServiceTests {

    private func makeService(_ files: [(name: String, text: String)])
        -> (MCPModelService, ProjectSession) {
        let session = makeSession(files, debounce: 10_000)
        let registry = OpenProjectRegistry()
        registry.register(session)
        return (MCPModelService(registry: registry), session)
    }

    // MARK: Projects

    @Test("Listing projects reports the counts and why generation is unavailable")
    func listingProjects() {
        let (service, _) = makeService([("a.model", Sample.broken)])
        let projects = service.listProjects()

        #expect(projects.count == 1)
        #expect(projects[0].name == "Untitled")
        #expect(projects[0].path == nil)
        #expect(projects[0].errorCount == 1)
        #expect(!projects[0].canGenerate)
        #expect(projects[0].generationBlocker == "Save the project first")
    }

    @Test("Opening something that is not a ModelForge bundle says so")
    func openingRefusesNonProjects() throws {
        let (service, _) = makeService([])
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let notAProject = directory.appendingPathComponent("notes.txt")
        try Data("hello".utf8).write(to: notAProject)

        do {
            _ = try service.openProject(path: notAProject.path)
            Issue.record("expected opening to fail")
        } catch {
            #expect(error.message.contains(".modelforge"))
        }

        do {
            _ = try service.openProject(path: directory.appendingPathComponent("gone.modelforge").path)
            Issue.record("expected opening to fail")
        } catch {
            #expect(error.message.contains("no such file"))
        }
    }

    // MARK: Reading

    @Test("Listing files reports line counts, problems and what each one declares")
    func listingFiles() throws {
        let (service, _) = makeService([("user.model", Sample.user), ("broken.model", Sample.broken)])
        let files = try service.listModelFiles(project: "Untitled")

        let user = try #require(files.first { $0.name == "user.model" })
        #expect(user.lineCount == 4)
        #expect(user.declares == ["User"])
        #expect(user.errorCount == 0)

        let broken = try #require(files.first { $0.name == "broken.model" })
        #expect(broken.errorCount == 1)
    }

    @Test("An empty file has no lines rather than one")
    func anEmptyFileHasNoLines() throws {
        let (service, _) = makeService([("empty.model", "")])
        let files = try service.listModelFiles(project: "Untitled")
        #expect(files[0].lineCount == 0)
    }

    @Test("A file can be named with or without its extension")
    func readingByNameOrStem() throws {
        let (service, _) = makeService([("user.model", Sample.user)])
        #expect(try service.readModelFile(project: "Untitled", file: "user.model") == Sample.user)
        #expect(try service.readModelFile(project: "Untitled", file: "user") == Sample.user)
        #expect(try service.readModelFile(project: "Untitled", file: "USER.MODEL") == Sample.user)
    }

    @Test("Asking for a file that is not there lists the ones that are")
    func readingAnUnknownFile() {
        let (service, _) = makeService([("user.model", Sample.user)])
        do {
            _ = try service.readModelFile(project: "Untitled", file: "payments")
            Issue.record("expected the read to fail")
        } catch {
            #expect(error.message.contains("payments"))
            #expect(error.message.contains("user.model"))
        }
    }

    // MARK: Writing

    @Test("Writing a file that does not exist creates it, extension included")
    func writingCreatesAFile() throws {
        let (service, session) = makeService([])
        let snapshot = try service.writeModelFile(project: "Untitled",
                                                  file: "user",
                                                  source: Sample.user)

        #expect(session.sources.map(\.name) == ["user.model"])
        #expect(snapshot.ok)
        #expect(snapshot.errorCount == 0)
        #expect(session.hasLocalEdits)
    }

    @Test("Writing a file that exists replaces its contents")
    func writingReplacesAFile() throws {
        let (service, session) = makeService([("user.model", "model Old {}")])
        _ = try service.writeModelFile(project: "Untitled", file: "User.Model", source: Sample.user)

        #expect(session.sources.count == 1)
        #expect(session.sources[0].text == Sample.user)
    }

    @Test("A write reports the whole project's problems, not just the file's")
    func writingReportsTheWholeProject() throws {
        // A change in one file routinely breaks — or fixes — another, so a write that looks
        // fine on its own still has to say what it did to the rest.
        let (service, _) = makeService([("account.model", Sample.account)])
        let snapshot = try service.writeModelFile(project: "Untitled",
                                                  file: "user",
                                                  source: "model NotUser {}")

        #expect(!snapshot.ok)
        #expect(snapshot.diagnostics.contains { $0.file == "account.model" })
        #expect(snapshot.rendered?.isEmpty == false)
    }

    @Test("A write is visible to the very next read, debounce or no debounce")
    func writesAreVisibleImmediately() throws {
        let (service, _) = makeService([])
        _ = try service.writeModelFile(project: "Untitled", file: "user", source: Sample.user)

        let files = try service.listModelFiles(project: "Untitled")
        #expect(files[0].declares == ["User"])
    }

    @Test("Creating refuses a name already in use, and says what to do instead")
    func creatingRefusesDuplicates() {
        let (service, _) = makeService([("user.model", Sample.user)])
        do {
            _ = try service.createModelFile(project: "Untitled", file: "user", source: "model X {}")
            Issue.record("expected the create to fail")
        } catch {
            #expect(error.message.contains("already exists"))
            #expect(error.message.contains("write_model_file"))
        }
    }

    @Test("Renaming goes through the same rules the file list enforces")
    func renaming() throws {
        let (service, session) = makeService([("user.model", Sample.user), ("other.model", "")])
        let files = try service.renameModelFile(project: "Untitled", file: "user", to: "people")

        #expect(session.sources.map(\.name) == ["other.model", "people.model"])
        #expect(files.map(\.name) == ["other.model", "people.model"])

        #expect(throws: MCPToolError.self) {
            try service.renameModelFile(project: "Untitled", file: "people", to: "other")
        }
    }

    @Test("Deleting says what happens to the code that file generated")
    func deleting() throws {
        let (service, session) = makeService([("user.model", Sample.user), ("other.model", "")])
        let message = try service.deleteModelFile(project: "Untitled", file: "user")

        #expect(session.sources.map(\.name) == ["other.model"])
        #expect(message.contains("user.model"))
        #expect(message.contains("removed on the next generate"))
    }

    // MARK: Checking without writing

    @Test("Checking a candidate compiles it against the project without saving it")
    func checkingDoesNotMutate() throws {
        let (service, session) = makeService([("account.model", Sample.account),
                                              ("user.model", Sample.user)])

        // Removing User would break Account, and the check has to see that.
        let snapshot = try service.checkSource(project: "Untitled",
                                               file: "user",
                                               source: "model Person {}")

        #expect(!snapshot.ok)
        #expect(snapshot.diagnostics.contains { $0.file == "account.model" })
        #expect(session.sources.first { $0.name == "user.model" }?.text == Sample.user)
        #expect(!session.hasLocalEdits)
    }

    @Test("Checking a file that does not exist yet adds it for the check only")
    func checkingANewFile() throws {
        let (service, session) = makeService([("account.model", Sample.account)])
        let snapshot = try service.checkSource(project: "Untitled",
                                               file: "user",
                                               source: Sample.user)

        #expect(snapshot.ok)
        #expect(session.sources.map(\.name) == ["account.model"])
    }

    // MARK: Diagnostics

    @Test("Diagnostics can be narrowed to one file, though the project still compiles whole")
    func diagnosticsForOneFile() throws {
        let (service, _) = makeService([("broken.model", Sample.broken),
                                        ("alsobroken.model", "model B { x: AlsoMissing }")])

        let all = try service.diagnostics(project: "Untitled", file: nil)
        #expect(all.errorCount == 2)

        let one = try service.diagnostics(project: "Untitled", file: "broken")
        #expect(one.errorCount == 1)
        #expect(one.diagnostics.allSatisfy { $0.file == "broken.model" })
        // `ok` is the project's verdict, not the file's — the rest of it is still broken.
        #expect(!one.ok)
    }

    @Test("A diagnostic carries the suggestion that goes with it")
    func diagnosticsCarryHelp() throws {
        let (service, _) = makeService([("user.model", Sample.user),
                                        ("a.model", "model A { owner: Usre }")])
        let snapshot = try service.diagnostics(project: "Untitled", file: "a")

        let problem = try #require(snapshot.diagnostics.first)
        #expect(problem.code == "unknownType")
        #expect(problem.help.contains { $0.contains("User") })
    }

    // MARK: Generated code

    @Test("Generated code can be asked for in one language")
    func filteringByLanguage() throws {
        let (service, _) = makeService([("user.model", Sample.user)])

        let both = try service.generatedCode(project: "Untitled", file: nil, language: nil)
        #expect(both.contains { $0.language == "swift" })
        #expect(both.contains { $0.language == "kotlin" })

        let swift = try service.generatedCode(project: "Untitled", file: nil, language: "Swift")
        #expect(swift.allSatisfy { $0.language == "swift" })
        #expect(!swift.isEmpty)
    }

    @Test("A language nobody generates is refused with the ones that work")
    func anUnknownLanguageIsRefused() {
        let (service, _) = makeService([("user.model", Sample.user)])
        do {
            _ = try service.generatedCode(project: "Untitled", file: nil, language: "rust")
            Issue.record("expected the request to fail")
        } catch {
            #expect(error.message.contains("swift"))
            #expect(error.message.contains("kotlin"))
        }
    }

    @Test("Asking what one file produces leaves out the project-wide support file")
    func filteringByFile() throws {
        let (service, _) = makeService([("user.model", Sample.user), ("account.model", Sample.account)])

        let all = try service.generatedCode(project: "Untitled", file: nil, language: "swift")
        #expect(all.contains { $0.from == nil })

        let one = try service.generatedCode(project: "Untitled", file: "user", language: "swift")
        #expect(one.count == 1)
        #expect(one[0].from == "user.model")
        #expect(one[0].contents.contains("struct User"))
    }

    // MARK: Generating to disk

    @Test("Generating an unsaved project is refused, phrased as the thing to fix")
    func generatingAnUnsavedProject() {
        let (service, _) = makeService([("user.model", Sample.user)])
        do {
            _ = try service.generate(project: "Untitled")
            Issue.record("expected generation to fail")
        } catch {
            #expect(error.message.contains("save the project first"))
        }
    }

    // MARK: Configuration

    @Test("Settings can be read back")
    func readingConfiguration() throws {
        let (service, _) = makeService([("a.model", "")])
        let configuration = try service.configuration(project: "Untitled")

        #expect(configuration.kotlinPackage == KotlinEmitterConfiguration.placeholderPackage)
        #expect(configuration.swiftAccessLevel == "internal")
        #expect(configuration.codable)
    }

    @Test("Settings can be changed one field at a time")
    func settingConfiguration() throws {
        let (service, session) = makeService([("a.model", "")])
        let updated = try service.setConfiguration(project: "Untitled",
                                                   kotlinPackage: "com.example.app",
                                                   kotlinOutput: "../android/generated",
                                                   swiftModule: nil,
                                                   swiftOutput: nil,
                                                   swiftAccessLevel: "public")

        #expect(updated.kotlinPackage == "com.example.app")
        #expect(updated.kotlinOutput == "../android/generated")
        #expect(updated.swiftAccessLevel == "public")
        // Untouched fields stay as they were.
        #expect(updated.swiftOutput == nil)
        #expect(session.hasLocalEdits)
    }

    @Test("An empty string clears an output path rather than setting it to nothing")
    func clearingAnOutputPath() throws {
        let (service, _) = makeService([("a.model", "")])
        _ = try service.setConfiguration(project: "Untitled", kotlinPackage: nil,
                                         kotlinOutput: "../android", swiftModule: nil,
                                         swiftOutput: nil, swiftAccessLevel: nil)
        let cleared = try service.setConfiguration(project: "Untitled", kotlinPackage: nil,
                                                   kotlinOutput: "", swiftModule: nil,
                                                   swiftOutput: nil, swiftAccessLevel: nil)
        #expect(cleared.kotlinOutput == nil)
    }

    @Test("An access level that does not exist is refused with the ones that do")
    func anUnknownAccessLevelIsRefused() {
        let (service, session) = makeService([("a.model", "")])
        do {
            _ = try service.setConfiguration(project: "Untitled", kotlinPackage: nil,
                                             kotlinOutput: nil, swiftModule: nil,
                                             swiftOutput: nil, swiftAccessLevel: "fileprivate")
            Issue.record("expected the change to fail")
        } catch {
            #expect(error.message.contains("internal"))
            #expect(error.message.contains("public"))
        }
        // Nothing was applied on the way to the refusal.
        #expect(!session.hasLocalEdits)
    }

    @Test("Every tool refuses a project that is not open")
    func toolsRefuseAnUnknownProject() {
        let (service, _) = makeService([("a.model", "")])
        #expect(throws: MCPToolError.self) { try service.listModelFiles(project: "Payments") }
        #expect(throws: MCPToolError.self) { try service.readModelFile(project: "Payments", file: "a") }
        #expect(throws: MCPToolError.self) { try service.diagnostics(project: "Payments", file: nil) }
        #expect(throws: MCPToolError.self) { try service.configuration(project: "Payments") }
    }
}
