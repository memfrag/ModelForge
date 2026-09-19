//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI
import ModelForgeKit

extension ProjectSession {

    /// The directory the project bundle sits in, which output paths are relative to.
    var projectDirectory: URL? {
        fileURL?.deletingLastPathComponent()
    }

    var swiftOutputDirectory: URL? {
        configuration.swift.output.flatMap {
            OutputLocation.resolve($0, relativeTo: projectDirectory)
        }
    }

    var kotlinOutputDirectory: URL? {
        configuration.kotlin.output.flatMap {
            OutputLocation.resolve($0, relativeTo: projectDirectory)
        }
    }

    var hasOutputDirectories: Bool {
        swiftOutputDirectory != nil || kotlinOutputDirectory != nil
    }

    /// Write the whole project's generated code.
    ///
    /// Always the whole project, never just the selected file: the manifest-based cleanup
    /// only knows what is stale by comparing a complete run against the previous one.
    func generate() {
        guard canGenerate, let generated else { return }

        guard hasOutputDirectories else {
            generationReport = GenerationReport(
                written: 0, unchanged: 0, removed: 0, destinations: [],
                failure: "Choose an output folder in Project Settings first.")
            return
        }

        let request = GeneratedFileWriter.Request(
            files: generated.files,
            previousManifest: document.manifest,
            swiftDirectory: swiftOutputDirectory,
            kotlinDirectory: kotlinOutputDirectory,
            projectDirectory: projectDirectory)

        Task { [weak self] in
            let outcome = await Task.detached(priority: .userInitiated) { () -> Swift.Result<GeneratedFileWriter.Result, any Error> in
                do {
                    return .success(try GeneratedFileWriter.write(request))
                } catch {
                    return .failure(error)
                }
            }.value

            guard let self else { return }
            switch outcome {
            case .success(let result):
                // Deliberately not marked as a local edit: the manifest is bookkeeping,
                // and treating it as unsaved work would make the watcher start asking
                // before reloading, instead of just adopting what is on disk.
                self.document.manifest = result.manifest
                self.generationReport = GenerationReport(written: result.written,
                                                         unchanged: result.unchanged,
                                                         removed: result.removed,
                                                         destinations: result.destinations,
                                                         failure: nil)
            case .failure(let error):
                self.generationReport = GenerationReport(
                    written: 0, unchanged: 0, removed: 0, destinations: [],
                    failure: error.localizedDescription)
            }
        }
    }

    func revealOutput() {
        let directories = [swiftOutputDirectory, kotlinOutputDirectory].compactMap { $0 }
        guard !directories.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(directories)
    }
}
