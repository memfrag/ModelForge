import Foundation
import Testing
@testable import ModelForgeKit

/// Fixture-backed comparison for generated source.
///
/// Emitter output is asserted against files on disk rather than inline strings, because
/// the point is that the *exact bytes* stay stable — and because a fixture is readable as
/// a sample of what the tool produces. Run with `RECORD_SNAPSHOTS=1` to rewrite them after
/// an intentional change, then read the diff before committing.
enum Snapshot {

    static var isRecording: Bool {
        ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "1"
    }

    /// This file's own path, captured here so the fixtures directory is the same wherever
    /// it is called from — a `#filePath` default parameter would resolve to the caller.
    private static let supportFilePath = #filePath

    /// The fixtures directory in the source tree, not the copied resource bundle, so
    /// recording writes somewhere that can be reviewed and committed.
    static func fixturesDirectory() -> URL {
        URL(fileURLWithPath: supportFilePath)
            .deletingLastPathComponent()   // Support/
            .deletingLastPathComponent()   // ModelForgeKitTests/
            .appendingPathComponent("Fixtures")
    }

    static func assert(_ actual: String,
                       matches path: String,
                       sourceLocation: Testing.SourceLocation = #_sourceLocation) {
        let url = fixturesDirectory().appendingPathComponent(path)

        guard let expected = try? String(contentsOf: url, encoding: .utf8) else {
            if isRecording {
                record(actual, to: url)
                return
            }
            Issue.record("""
            Missing fixture: \(path)
            Re-run with RECORD_SNAPSHOTS=1 to create it.
            """, sourceLocation: sourceLocation)
            return
        }

        guard actual != expected else { return }

        if isRecording {
            record(actual, to: url)
            return
        }

        Issue.record("""
        \(path) does not match.

        --- expected ---
        \(expected)
        --- actual ---
        \(actual)
        ---
        Re-run with RECORD_SNAPSHOTS=1 to update, then read the diff.
        """, sourceLocation: sourceLocation)
    }

    private static func record(_ contents: String, to url: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? contents.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Every `.model` file in a fixture project, sorted by name so file ids are stable.
    static func project(_ name: String) -> [SourceFile] {
        let directory = fixturesDirectory()
            .appendingPathComponent("Generation/\(name)/input")
        let contents = (try? FileManager.default.contentsOfDirectory(at: directory,
                                                                     includingPropertiesForKeys: nil)) ?? []
        return contents
            .filter { $0.pathExtension == "model" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .enumerated()
            .compactMap { index, url in
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
                return SourceFile(id: SourceFileID(index), name: url.lastPathComponent, text: text)
            }
    }
}
