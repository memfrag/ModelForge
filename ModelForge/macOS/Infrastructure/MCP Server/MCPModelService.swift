//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import AppKit
import SwiftUI
import ModelForgeKit

/// What the MCP tools actually do, against the projects open in the app.
///
/// `@MainActor` and therefore implicitly `Sendable`, which is what lets the `@Sendable` tool
/// handlers capture it and `await` straight into it — the actor hop is the whole bridge, with no
/// `MainActor.run` anywhere.
///
/// Every read compiles the project synchronously rather than reading whatever the window last
/// produced. The UI's compile is debounced by design, so a tool that asked for diagnostics
/// immediately after a write would otherwise report the state from before it.
@MainActor final class MCPModelService {

    private let registry: OpenProjectRegistry

    init(registry: OpenProjectRegistry) {
        self.registry = registry
    }

    // MARK: - Projects

    func listProjects() -> [MCPProjectSnapshot] {
        registry.sessions.map(snapshot(of:))
    }

    func openProject(path: String) throws(MCPToolError) -> MCPProjectSnapshot {
        let expanded = (path as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded)

        guard FileManager.default.fileExists(atPath: url.path) else {
            throw .openFailed(path: path, reason: "no such file.")
        }
        guard url.pathExtension == ProjectLayout.bundleExtension else {
            throw .openFailed(path: path,
                              reason: "a ModelForge project is a .\(ProjectLayout.bundleExtension) bundle.")
        }

        if let already = registry.sessions.first(where: { $0.fileURL?.standardizedFileURL == url.standardizedFileURL }) {
            return snapshot(of: already)
        }

        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
        throw .openFailed(path: path,
                          reason: "the window is opening. Call list_projects again in a moment.")
    }

    // MARK: - Model files

    func listModelFiles(project query: String) throws(MCPToolError) -> [ModelFileSnapshot] {
        let session = try registry.session(matching: query)
        let result = compile(session)

        return session.document.sources.map { source in
            let problems = result.diagnostics(in: source.id)
            return ModelFileSnapshot(
                name: source.name,
                lineCount: source.text.isEmpty ? 0 : source.text.split(separator: "\n", omittingEmptySubsequences: false).count,
                errorCount: problems.count { $0.severity == .error },
                warningCount: problems.count { $0.severity == .warning },
                declares: result.module.types(in: source.id).map(\.name))
        }
    }

    func readModelFile(project query: String, file: String) throws(MCPToolError) -> String {
        let session = try registry.session(matching: query)
        return try source(in: session, named: file).text
    }

    /// Replace a file's contents, creating it when it does not exist.
    ///
    /// Returns the diagnostics for the whole project afterwards, because a change in one file
    /// routinely breaks — or fixes — another.
    func writeModelFile(project query: String,
                        file: String,
                        source text: String) throws(MCPToolError) -> CompileSnapshot {
        let session = try registry.session(matching: query)
        let name = normalizedFileName(file)

        if let existing = session.document.sources.first(where: { $0.name.lowercased() == name.lowercased() }) {
            session.document.updateText(text, for: existing.id)
        } else {
            session.document.appendSource(named: name, text: text)
        }
        session.markEdited()
        session.compileNow()

        return CompileSnapshot(compile(session))
    }

    func createModelFile(project query: String,
                         file: String,
                         source text: String) throws(MCPToolError) -> CompileSnapshot {
        let session = try registry.session(matching: query)
        let name = normalizedFileName(file)
        guard session.document.isNameAvailable(name) else {
            throw .fileAlreadyExists(name)
        }
        return try writeModelFile(project: query, file: name, source: text)
    }

    func renameModelFile(project query: String,
                         file: String,
                         to newName: String) throws(MCPToolError) -> [ModelFileSnapshot] {
        let session = try registry.session(matching: query)
        let existing = try source(in: session, named: file)

        if let problem = session.rename(existing.id, to: newName) {
            throw .invalidArgument(problem)
        }
        return try listModelFiles(project: query)
    }

    func deleteModelFile(project query: String, file: String) throws(MCPToolError) -> String {
        let session = try registry.session(matching: query)
        let existing = try source(in: session, named: file)
        session.delete(existing.id)
        return "Deleted \(existing.name). The code generated from it is removed on the next generate."
    }

    // MARK: - Compiling

    func diagnostics(project query: String, file: String?) throws(MCPToolError) -> CompileSnapshot {
        let session = try registry.session(matching: query)
        let result = compile(session)
        guard let file else { return CompileSnapshot(result) }
        return CompileSnapshot(result, limitedTo: try source(in: session, named: file).id)
    }

    /// Compile a candidate version of a file without saving it.
    ///
    /// The point is to let an agent check a change before committing to it. The rest of the
    /// project is included, so cross-file references resolve exactly as they would after a write.
    func checkSource(project query: String,
                     file: String,
                     source text: String) throws(MCPToolError) -> CompileSnapshot {
        let session = try registry.session(matching: query)
        let name = normalizedFileName(file)

        var files = session.document.sourceFiles
        if let index = files.firstIndex(where: { $0.name.lowercased() == name.lowercased() }) {
            files[index] = SourceFile(id: files[index].id, name: name, text: text)
        } else {
            let nextID = SourceFileID((files.map(\.id.rawValue).max() ?? -1) + 1)
            files.append(SourceFile(id: nextID, name: name, text: text))
        }
        return CompileSnapshot(Compiler.compile(files))
    }

    // MARK: - Generated code

    func generatedCode(project query: String,
                       file: String?,
                       language: String?) throws(MCPToolError) -> [GeneratedCodeSnapshot] {
        let session = try registry.session(matching: query)
        let result = compile(session)
        let output = Generator.generate(result, configuration: session.configuration)

        let wanted: Language?
        switch language?.lowercased() {
        case nil, "", "both": wanted = nil
        case "swift": wanted = .swift
        case "kotlin": wanted = .kotlin
        default:
            throw .invalidArgument("language must be \"swift\", \"kotlin\" or \"both\".")
        }

        // Written out rather than via `Optional.map`, which cannot carry a typed throw.
        var sourceID: SourceFileID?
        if let file {
            sourceID = try source(in: session, named: file).id
        }
        let names = Dictionary(uniqueKeysWithValues: result.files.map { ($0.id, $0.name) })

        return output.files
            .filter { wanted == nil || $0.language == wanted }
            // A named file means "what does this produce"; the support file belongs to the
            // project as a whole, so it is only included when nothing was named.
            .filter { sourceID == nil || $0.sourceFile == sourceID }
            .map {
                GeneratedCodeSnapshot(name: $0.name,
                                      language: $0.language.rawValue,
                                      from: $0.sourceFile.flatMap { names[$0] },
                                      contents: $0.contents)
            }
    }

    // MARK: - Generating to disk

    func generate(project query: String) throws(MCPToolError) -> GenerationSnapshot {
        let session = try registry.session(matching: query)

        // The same rules the Generate menu item enforces, so an agent cannot do something the
        // user is prevented from doing by hand.
        if let blocker = session.generationBlocker, session.result != nil || session.fileURL == nil {
            throw .cannotGenerate(reason: blocker.lowercased())
        }

        let result = compile(session)
        guard !result.hasErrors else {
            throw .cannotGenerate(reason: "the project has \(result.errorCount) error(s)")
        }
        guard session.hasOutputDirectories else {
            throw .noOutputConfigured
        }

        let request = GeneratedFileWriter.Request(
            files: Generator.generate(result, configuration: session.configuration).files,
            previousManifest: session.document.manifest,
            swiftDirectory: session.swiftOutputDirectory,
            kotlinDirectory: session.kotlinOutputDirectory,
            projectDirectory: session.projectDirectory)

        do {
            let outcome = try GeneratedFileWriter.write(request)
            session.document.manifest = outcome.manifest
            return GenerationSnapshot(written: outcome.written,
                                      unchanged: outcome.unchanged,
                                      removed: outcome.removed,
                                      swiftOutput: session.swiftOutputDirectory?.path,
                                      kotlinOutput: session.kotlinOutputDirectory?.path)
        } catch {
            throw .cannotGenerate(reason: error.localizedDescription)
        }
    }

    // MARK: - Configuration

    func configuration(project query: String) throws(MCPToolError) -> ConfigurationSnapshot {
        snapshot(of: try registry.session(matching: query).configuration)
    }

    func setConfiguration(project query: String,
                          kotlinPackage: String?,
                          kotlinOutput: String?,
                          swiftModule: String?,
                          swiftOutput: String?,
                          swiftAccessLevel: String?) throws(MCPToolError) -> ConfigurationSnapshot {
        let session = try registry.session(matching: query)

        var accessLevel: SwiftEmitterConfiguration.AccessLevel?
        if let swiftAccessLevel {
            guard let parsed = SwiftEmitterConfiguration.AccessLevel(rawValue: swiftAccessLevel) else {
                throw .invalidArgument("swift_access_level must be \"internal\" or \"public\".")
            }
            accessLevel = parsed
        }

        session.updateConfiguration { configuration in
            if let kotlinPackage { configuration.kotlin.package = kotlinPackage }
            if let kotlinOutput { configuration.kotlin.output = kotlinOutput.isEmpty ? nil : kotlinOutput }
            if let swiftModule { configuration.swift.module = swiftModule.isEmpty ? nil : swiftModule }
            if let swiftOutput { configuration.swift.output = swiftOutput.isEmpty ? nil : swiftOutput }
            if let accessLevel { configuration.swift.accessLevel = accessLevel }
        }
        return snapshot(of: session.configuration)
    }

    // MARK: - Helpers

    /// Compile the project as it stands right now.
    private func compile(_ session: ProjectSession) -> CompilationResult {
        Compiler.compile(session.document.sourceFiles)
    }

    private func source(in session: ProjectSession, named query: String) throws(MCPToolError) -> ProjectSource {
        let wanted = normalizedFileName(query).lowercased()
        let stem = (query as NSString).deletingPathExtension.lowercased()

        if let match = session.document.sources.first(where: { $0.name.lowercased() == wanted })
            ?? session.document.sources.first(where: { $0.displayName.lowercased() == stem }) {
            return match
        }
        throw .fileNotFound(project: session.projectName,
                            query: query,
                            available: session.document.sources.map(\.name))
    }

    private func normalizedFileName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.hasSuffix(".\(ProjectLayout.sourceExtension)")
            ? trimmed
            : "\(trimmed).\(ProjectLayout.sourceExtension)"
    }

    private func snapshot(of session: ProjectSession) -> MCPProjectSnapshot {
        let result = compile(session)
        return MCPProjectSnapshot(
            name: session.projectName,
            path: session.fileURL?.path,
            modelFiles: session.document.sources.map(\.name),
            errorCount: result.errorCount,
            warningCount: result.warningCount,
            kotlinPackage: session.configuration.kotlin.package,
            swiftOutput: session.configuration.swift.output,
            kotlinOutput: session.configuration.kotlin.output,
            canGenerate: !result.hasErrors && session.hasOutputDirectories
                && session.configuration.kotlin.isPackageConfigured && session.fileURL != nil,
            generationBlocker: session.generationBlocker)
    }

    private func snapshot(of configuration: ProjectConfiguration) -> ConfigurationSnapshot {
        ConfigurationSnapshot(
            kotlinPackage: configuration.kotlin.package,
            kotlinOutput: configuration.kotlin.output,
            swiftModule: configuration.swift.module,
            swiftOutput: configuration.swift.output,
            swiftAccessLevel: configuration.swift.accessLevel.rawValue,
            codable: configuration.swift.codable,
            equatable: configuration.swift.equatable,
            hashable: configuration.swift.hashable,
            sendable: configuration.swift.sendable)
    }
}
