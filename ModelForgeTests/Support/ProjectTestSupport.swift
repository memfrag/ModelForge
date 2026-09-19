//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation
import ModelForgeKit
@testable import ModelForge

// Shared scaffolding for the app-target suites.
//
// Two things are worth knowing before reading the tests themselves:
//
// - `URLDocumentConfiguration` has no public initialiser, so a document built here can
//   never have a `fileURL`. Every test project is therefore an unsaved one called
//   "Untitled", and anything gated on having been saved — Generate, most of all — can only
//   be observed being refused. `ProjectBundleTests` in the Kit covers the saved side.
// - The session compiles on a detached task and delivers the result back on the main
//   actor, so a test has to actually give the main actor up. That is what `waitUntil` is
//   for; polling is the honest way to observe work that is deliberately asynchronous.

/// A session over an in-memory project.
///
/// - Parameter debounce: milliseconds. Zero by default, so a test that only wants a
///   compiled result does not spend a third of a second waiting for one.
@MainActor
func makeSession(_ files: [(name: String, text: String)] = [],
                 debounce: Int = 0) -> ProjectSession {
    ProjectSession(document: makeDocument(files), settings: makeSettings(debounce: debounce))
}

@MainActor
func makeDocument(_ files: [(name: String, text: String)] = []) -> ProjectDocument {
    ProjectDocument(snapshot: makeSnapshot(files))
}

func makeSnapshot(_ files: [(name: String, text: String)] = [],
                  configuration: ProjectConfiguration = .default,
                  manifest: GenerationManifest = GenerationManifest()) -> ProjectSnapshot {
    let sources = files.enumerated().map { index, file in
        ProjectSource(id: SourceFileID(index), name: file.name, text: file.text)
    }
    return ProjectSnapshot(sources: sources, configuration: configuration, manifest: manifest)
}

@MainActor
func makeSettings(debounce: Int = 0) -> AppSettings {
    let settings = AppSettings.mock()
    settings.previewDebounceMilliseconds = debounce
    return settings
}

/// Give the main actor up until `condition` holds.
///
/// - Returns: whether it held before the timeout, so the caller can `#expect` it and get a
///   failure pointing at the test rather than at this helper.
@MainActor
func waitUntil(timeout: Duration = .seconds(5), _ condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(2))
    }
    return condition()
}

/// Wait for the session to hold a compiled result that knows about `type`.
///
/// Waiting on the *content* rather than on "a result exists" is what makes the staleness
/// tests mean anything: an older compile landing late would satisfy the weaker condition.
@MainActor
func waitForType(_ type: String, in session: ProjectSession) async -> Bool {
    await waitUntil { session.knownTypeNames.contains(type) }
}

// MARK: - Sample sources

enum Sample {

    static let user = """
        model User {
            id: UUID
            name: String
        }

        """

    static let account = """
        model Account {
            owner: User
            balance: Int64
        }

        """

    /// References a type that does not exist, so the project has exactly one error.
    static let broken = """
        model Broken {
            owner: NoSuchType
        }
        """

    /// Does not parse at all, which is what the formatter refuses to touch.
    static let unparseable = "model Unclosed {\n    name: String\n"

    /// Correct, but not in canonical layout.
    static let messy = "model   Messy{\n  name:String\n}\n"
}
