//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI
import UniformTypeIdentifiers
import ModelForgeKit

/// An open ModelForge project.
///
/// A file package holding the project's `.model` files, its `Config.json` and the manifest
/// of what it last generated — several files that have to travel together — while each
/// `.model` inside stays plain UTF-8 text that `grep`, `git diff` and any other editor can
/// still read. The bundle is a container, not an encoding.
///
/// Built on the `Document` protocol, so the type is an ordinary `@Observable` class: views
/// read it directly, mutating it marks the project dirty, and reading and writing happen
/// off the main actor through a plain-value `ProjectSnapshot`.
@Observable @MainActor final class ProjectDocument: Document {

    nonisolated static var readableContentTypes: [UTType] { [.modelForgeProject] }

    private(set) var sources: [ProjectSource]
    var configuration: ProjectConfiguration
    var manifest: GenerationManifest

    /// The `Config.json` exactly as read, so keys written by a newer version of ModelForge
    /// survive being saved by this one.
    private(set) var rawConfiguration: JSONValue?

    /// Problems found while opening, surfaced in the window rather than thrown away.
    private(set) var loadWarnings: [String] = []

    /// Where the bundle lives. Kept so output paths, which are relative to the project,
    /// can be resolved — and so a Save As is noticed.
    @ObservationIgnored
    private(set) weak var urlConfiguration: URLDocumentConfiguration?

    var fileURL: URL? { urlConfiguration?.fileURL }

    private var nextFileID: Int

    // MARK: Creating

    init(snapshot: ProjectSnapshot = .starter, urlConfiguration: URLDocumentConfiguration? = nil) {
        sources = snapshot.sources
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        configuration = snapshot.configuration
        rawConfiguration = snapshot.rawConfiguration
        loadWarnings = snapshot.warnings
        manifest = snapshot.manifest
        nextFileID = (snapshot.sources.map(\.id.rawValue).max() ?? -1) + 1
        self.urlConfiguration = urlConfiguration
    }

    // MARK: Document

    nonisolated func reader(configuration: sending ReadConfiguration) -> sending FileWrapperDocumentReader<ProjectSnapshot> {
        FileWrapperDocumentReader(configuration) { wrapper in
            try ProjectSnapshot(wrapper: wrapper)
        }
    }

    nonisolated func writer(configuration: sending WriteConfiguration) -> sending FileWrapperDocumentWriter<ProjectSnapshot> {
        FileWrapperDocumentWriter(configuration) { snapshot, _ in
            try snapshot.fileWrapper()
        }
    }

    /// Adopt what was read from disk.
    ///
    /// Ids of files whose names still exist are kept, so the selection and each file's undo
    /// history survive a reload — which is what makes switching git branches under an open
    /// window unremarkable.
    func apply(snapshot: sending ProjectSnapshot, previous: sending ProjectSnapshot?) async throws {
        var adopted: [ProjectSource] = []
        for incoming in snapshot.sources {
            if let existing = sources.first(where: { $0.name == incoming.name }) {
                adopted.append(ProjectSource(id: existing.id, name: incoming.name, text: incoming.text))
            } else {
                adopted.append(ProjectSource(id: SourceFileID(nextFileID),
                                             name: incoming.name,
                                             text: incoming.text))
                nextFileID += 1
            }
        }
        sources = adopted.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        configuration = snapshot.configuration
        rawConfiguration = snapshot.rawConfiguration
        loadWarnings = snapshot.warnings

        // An absent manifest means the project on disk has no record of what it generated,
        // not that it generated nothing. Discarding what this window already knows would
        // orphan the files written before the reload.
        if !snapshot.manifest.isEmpty {
            manifest = snapshot.manifest
        }
    }

    func snapshot(contentType: UTType) async throws -> sending ProjectSnapshot {
        ProjectSnapshot(sources: sources,
                        configuration: configuration,
                        rawConfiguration: rawConfiguration,
                        manifest: manifest)
    }

    func adopt(urlConfiguration: URLDocumentConfiguration) {
        self.urlConfiguration = urlConfiguration
    }

    // MARK: Editing

    @discardableResult
    func appendSource(named name: String, text: String) -> SourceFileID {
        let id = SourceFileID(nextFileID)
        nextFileID += 1
        sources.append(ProjectSource(id: id, name: name, text: text))
        sortSources()
        return id
    }

    func removeSource(_ id: SourceFileID) {
        sources.removeAll { $0.id == id }
    }

    func renameSource(_ id: SourceFileID, to newName: String) {
        guard let index = sources.firstIndex(where: { $0.id == id }) else { return }
        sources[index].name = newName
        sortSources()
    }

    func updateText(_ text: String, for id: SourceFileID) {
        guard let index = sources.firstIndex(where: { $0.id == id }) else { return }
        guard sources[index].text != text else { return }
        sources[index].text = text
    }

    subscript(id: SourceFileID) -> ProjectSource? {
        sources.first { $0.id == id }
    }

    /// Whether `name` is free, ignoring `excluding` so renaming a file to its own name is
    /// not reported as a collision.
    func isNameAvailable(_ name: String, excluding id: SourceFileID? = nil) -> Bool {
        guard !ProjectLayout.reservedFileNames.contains(name) else { return false }
        return !sources.contains { $0.id != id && $0.name.lowercased() == name.lowercased() }
    }

    /// `Untitled.model`, `Untitled 2.model`, …
    func availableName(basedOn base: String) -> String {
        let stem = (base as NSString).deletingPathExtension
        var candidate = "\(stem).\(ProjectLayout.sourceExtension)"
        var counter = 2
        while !isNameAvailable(candidate) {
            candidate = "\(stem) \(counter).\(ProjectLayout.sourceExtension)"
            counter += 1
        }
        return candidate
    }

    private func sortSources() {
        sources.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var sourceFiles: [SourceFile] {
        sources.map(\.sourceFile)
    }
}
