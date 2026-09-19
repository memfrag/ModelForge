//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation
import ModelForgeKit

/// A project's contents as plain values.
///
/// The `Document` protocol reads and writes through a snapshot so that file I/O happens
/// off the main actor while the document itself stays main-actor bound. Everything in here
/// is a value type, so it crosses that boundary with no locking.
nonisolated struct ProjectSnapshot: Sendable, Hashable {

    var sources: [ProjectSource]
    var configuration: ProjectConfiguration
    /// The `Config.json` exactly as read, so keys written by a newer version of ModelForge
    /// survive being saved by this one.
    var rawConfiguration: JSONValue?
    var manifest: GenerationManifest
    /// Problems found while reading, surfaced in the window rather than thrown away.
    var warnings: [String] = []

    init(sources: [ProjectSource] = [],
         configuration: ProjectConfiguration = .default,
         rawConfiguration: JSONValue? = nil,
         manifest: GenerationManifest = GenerationManifest(),
         warnings: [String] = []) {
        self.sources = sources
        self.configuration = configuration
        self.rawConfiguration = rawConfiguration
        self.manifest = manifest
        self.warnings = warnings
    }

    /// What a brand-new project contains.
    ///
    /// One worked example rather than an empty project, so both previews are populated the
    /// moment a window opens and the language teaches itself.
    static var starter: ProjectSnapshot {
        ProjectSnapshot(sources: [
            ProjectSource(id: SourceFileID(0),
                          name: ProjectLayout.starterFileName,
                          text: ProjectLayout.starterSource)
        ])
    }

    // MARK: Reading

    init(wrapper: FileWrapper) throws {
        guard let wrappers = wrapper.fileWrappers else {
            throw CocoaError(.fileReadCorruptFile)
        }

        var configuration = ProjectConfiguration.default
        var rawConfiguration: JSONValue?
        var manifest = GenerationManifest()
        var warnings: [String] = []

        // Configuration first: a newer format means the project must not open at all,
        // rather than open with settings we do not understand quietly discarded.
        if let data = wrappers[ProjectLayout.configurationFileName]?.regularFileContents {
            do {
                let loaded = try ConfigurationStore.load(from: data)
                configuration = loaded.configuration
                rawConfiguration = loaded.raw
            } catch let error as ConfigurationStore.LoadError {
                switch error {
                case .newerFormat(let found, let supported):
                    throw ProjectLoadError.newerFormat(found: found, supported: supported)
                case .unreadable(let detail):
                    warnings.append("\(detail) Default settings are being used.")
                }
            }
        }

        if let data = wrappers[ProjectLayout.manifestFileName]?.regularFileContents {
            manifest = GenerationManifest.decoded(from: data)
        }

        // Sorted, so file ids — and therefore the order of generated output — are stable.
        var sources: [ProjectSource] = []
        for name in wrappers.keys.sorted() where ProjectLayout.isSourceFile(name) {
            guard let data = wrappers[name]?.regularFileContents else { continue }
            guard let text = String(data: data, encoding: .utf8) else {
                warnings.append("\(name) is not valid UTF-8 and was not opened.")
                continue
            }
            sources.append(ProjectSource(id: SourceFileID(sources.count), name: name, text: text))
        }

        self.init(sources: sources,
                  configuration: configuration,
                  rawConfiguration: rawConfiguration,
                  manifest: manifest,
                  warnings: warnings)
    }

    // MARK: Writing

    func fileWrapper() throws -> FileWrapper {
        var wrappers: [String: FileWrapper] = [:]

        for source in sources {
            // Verbatim UTF-8: no BOM, no newline normalization. These are source files
            // that people read in diffs.
            wrappers[source.name] = FileWrapper(regularFileWithContents: Data(source.text.utf8))
        }

        wrappers[ProjectLayout.configurationFileName] = FileWrapper(
            regularFileWithContents: try ConfigurationStore.data(for: configuration,
                                                                 preserving: rawConfiguration))

        if !manifest.isEmpty {
            wrappers[ProjectLayout.manifestFileName] =
                FileWrapper(regularFileWithContents: try manifest.encoded())
        }

        return FileWrapper(directoryWithFileWrappers: wrappers)
    }
}

/// A reason a project could not be opened.
nonisolated enum ProjectLoadError: LocalizedError {
    case newerFormat(found: Int, supported: Int)

    var errorDescription: String? {
        switch self {
        case .newerFormat:
            "This project was created by a newer version of ModelForge."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .newerFormat(let found, let supported):
            """
            It uses project format \(found), and this version understands format \(supported). \
            Update ModelForge to open it.

            Your model files are plain text and have not been changed.
            """
        }
    }
}
