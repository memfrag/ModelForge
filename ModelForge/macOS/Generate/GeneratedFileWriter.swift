//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation
import ModelForgeKit

/// Writes generated code to disk and removes what it no longer produces.
nonisolated enum GeneratedFileWriter {

    struct Request: Sendable {
        let files: [GeneratedFile]
        /// Paths, relative to the project, written by the previous run.
        let previousManifest: GenerationManifest
        let swiftDirectory: URL?
        let kotlinDirectory: URL?
        let projectDirectory: URL?
    }

    struct Result: Sendable {
        var written = 0
        var unchanged = 0
        var removed = 0
        var destinations: [URL] = []
        var manifest = GenerationManifest()
    }

    enum WriteError: LocalizedError {
        case noDestination

        var errorDescription: String? {
            switch self {
            case .noDestination:
                "Choose at least one output folder in Project Settings."
            }
        }
    }

    static func write(_ request: Request) throws -> Result {
        guard request.swiftDirectory != nil || request.kotlinDirectory != nil else {
            throw WriteError.noDestination
        }

        var result = Result()
        var swiftWritten: [String] = []
        var kotlinWritten: [String] = []

        for file in request.files {
            let directory = switch file.language {
            case .swift: request.swiftDirectory
            case .kotlin: request.kotlinDirectory
            }
            guard let directory else { continue }

            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent(file.name)

            // Only write when the bytes actually differ. Generation is deterministic, so
            // an unchanged file keeps its modification date — which is what stops Xcode
            // and Gradle rebuilding the world after every Generate.
            if let existing = try? String(contentsOf: url, encoding: .utf8), existing == file.contents {
                result.unchanged += 1
            } else {
                try file.contents.write(to: url, atomically: true, encoding: .utf8)
                result.written += 1
            }

            let recorded = OutputLocation.relativePath(from: request.projectDirectory, to: url)
            switch file.language {
            case .swift: swiftWritten.append(recorded)
            case .kotlin: kotlinWritten.append(recorded)
            }

            if !result.destinations.contains(directory) {
                result.destinations.append(directory)
            }
        }

        result.manifest = GenerationManifest(swiftFiles: swiftWritten, kotlinFiles: kotlinWritten)
        result.removed = removeStale(previous: request.previousManifest,
                                     current: result.manifest,
                                     projectDirectory: request.projectDirectory)
        return result
    }

    /// Delete files the previous run wrote that this one did not.
    ///
    /// This is what stops a renamed or deleted model leaving a stale generated type behind
    /// that still compiles into the apps. Only paths recorded in our own manifest are
    /// considered, so hand-written code sharing an output folder is never touched.
    private static func removeStale(previous: GenerationManifest,
                                    current: GenerationManifest,
                                    projectDirectory: URL?) -> Int {
        let obsolete = Set(previous.swiftFiles + previous.kotlinFiles)
            .subtracting(current.swiftFiles + current.kotlinFiles)

        var removed = 0
        for path in obsolete.sorted() {
            guard let url = OutputLocation.resolve(path, relativeTo: projectDirectory) else { continue }
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            do {
                try FileManager.default.removeItem(at: url)
                removed += 1
            } catch {
                // A file we cannot delete is not worth failing the whole generate over;
                // the manifest simply stops tracking it.
                continue
            }
        }
        return removed
    }
}
