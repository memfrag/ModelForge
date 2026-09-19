//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI
import AppKit
import ModelForgeKit

/// The live state of one open project window.
///
/// Owns the debounce, runs the compiler off the main actor, holds the most recent result
/// the previews are drawn from, and keeps one `UndoManager` per file. The document owns
/// persistence; this owns everything that changes while you type.
///
/// The document is an `@Observable` class owned by the `DocumentGroup`, so mutating it
/// here goes through the ordinary document machinery and the project is marked dirty and
/// autosaved with nothing extra to call.
@Observable @MainActor final class ProjectSession {

    /// What the middle and right columns are showing.
    enum Selection: Hashable {
        case settings
        case file(SourceFileID)
    }

    let document: ProjectDocument

    /// Where the project bundle lives. Output paths resolve against its directory, so a
    /// project that has never been saved cannot generate yet.
    var fileURL: URL? { document.fileURL }

    var selection: Selection {
        didSet {
            if case .file(let id) = selection { lastSelectedFile = id }
        }
    }

    private(set) var lastSelectedFile: SourceFileID?

    /// The most recent completed compile. Never cleared while typing, which is what keeps
    /// the previews and the problems list populated mid-keystroke.
    private(set) var result: CompilationResult?
    private(set) var generated: GeneratedOutput?

    var previewLanguage: Language = .swift

    /// Set when the user picks a problem; consumed by the editor to select that range.
    var pendingSelection: SourceRange?

    var isProblemsListExpanded = false

    /// The outcome of the last Generate, shown as a transient banner.
    var generationReport: GenerationReport?

    /// Set when the project changed on disk while there were unsaved edits.
    var externalChange: ExternalChange?

    /// Whether this window holds edits that have not reached disk yet.
    ///
    /// The watcher needs an answer the moment an event arrives, and autosave runs on its
    /// own schedule, so this is tracked here rather than asked of the document.
    private(set) var hasLocalEdits = false

    /// One undo history per file.
    ///
    /// Per file rather than per project: ⌘Z after switching files should not reach back
    /// into the file you were editing before, which is how Xcode behaves. Held here so it
    /// survives the editor view being rebuilt, and so the document can stay a value type.
    @ObservationIgnored
    private var undoManagers: [SourceFileID: UndoManager] = [:]

    @ObservationIgnored
    private var compileTask: Task<Void, Never>?

    @ObservationIgnored
    private var textVersion = 0

    @ObservationIgnored
    private let settings: AppSettings

    init(document: ProjectDocument, settings: AppSettings) {
        self.document = document
        self.settings = settings
        self.selection = document.sources.first.map { Selection.file($0.id) } ?? .settings
    }

    // MARK: Document access

    var sources: [ProjectSource] { document.sources }

    var configuration: ProjectConfiguration { document.configuration }

    var selectedSource: ProjectSource? {
        guard case .file(let id) = selection else { return nil }
        return document[id]
    }

    /// The undo history for a file, created the first time it is edited.
    func undoManager(for id: SourceFileID) -> UndoManager {
        if let existing = undoManagers[id] { return existing }
        let manager = UndoManager()
        undoManagers[id] = manager
        return manager
    }

    // MARK: Editing

    /// Called on every keystroke.
    ///
    /// Writing through the binding is what marks the project dirty; the debounce, the
    /// off-main compile and the stale-result guard are all below. The version counter
    /// guarantees a slow older compile can never overwrite a newer result.
    func updateText(_ text: String, for id: SourceFileID) {
        guard document[id]?.text != text else { return }
        document.updateText(text, for: id)
        hasLocalEdits = true
    }

    /// The project's sources changed — by typing, by a file operation, or by the document
    /// adopting what was read from disk.
    ///
    /// Compilation is driven from observing the document rather than from each mutation,
    /// so a change made by `apply(snapshot:previous:)` — which SwiftUI calls on the
    /// document directly, behind the session's back — cannot leave the previews stale.
    func sourcesChanged() {
        repairSelectionIfNeeded()
        scheduleCompile(debounced: true)
    }

    func configurationChanged() {
        compileNow()
    }

    /// Keep the selection pointing at something that still exists.
    private func repairSelectionIfNeeded() {
        if case .file(let id) = selection, document[id] == nil {
            if let preferred = lastSelectedFile, document[preferred] != nil {
                selection = .file(preferred)
            } else {
                selection = document.sources.first.map { Selection.file($0.id) } ?? .settings
            }
        } else if case .settings = selection, lastSelectedFile == nil,
                  let first = document.sources.first {
            selection = .file(first.id)
        }
    }

    /// Recompile immediately, for changes that are not keystrokes — adding a file,
    /// changing configuration, reloading from disk.
    func compileNow() {
        scheduleCompile(debounced: false)
    }

    private func scheduleCompile(debounced: Bool) {
        textVersion += 1
        let version = textVersion
        let files = document.sourceFiles
        let configuration = document.configuration
        let delay = settings.previewDebounceMilliseconds

        compileTask?.cancel()
        compileTask = Task { [weak self] in
            if debounced {
                guard (try? await Task.sleep(for: .milliseconds(delay))) != nil else { return }
            }

            // Detached on purpose: under SE-0461, simply awaiting a nonisolated async
            // function would run it straight back on the main actor.
            let output = await Task.detached(priority: .userInitiated) {
                CompilePipeline.run(files: files, configuration: configuration)
            }.value

            guard !Task.isCancelled, let self, self.textVersion == version else { return }
            self.result = output.result
            self.generated = output.generated
        }
    }

    // MARK: Derived state

    var diagnostics: [Diagnostic] { result?.diagnostics ?? [] }

    var hasErrors: Bool { result?.hasErrors ?? false }

    var statusSummary: String { result?.summary ?? "Compiling…" }

    func diagnostics(for id: SourceFileID) -> [Diagnostic] {
        result?.diagnostics(in: id) ?? []
    }

    /// The worst problem in a file, for the badge in the file list.
    func worstSeverity(for id: SourceFileID) -> Diagnostic.Severity? {
        diagnostics(for: id).map(\.severity).max()
    }

    /// Problems ordered so the selected file's come first. You care most about where you
    /// are, but you still need to see that another file is broken.
    var orderedDiagnostics: [Diagnostic] {
        guard case .file(let id) = selection else { return diagnostics }
        return diagnostics.filter { $0.range.file == id } + diagnostics.filter { $0.range.file != id }
    }

    func fileName(for id: SourceFileID) -> String {
        document[id]?.name ?? "?"
    }

    func previewFile(for language: Language) -> GeneratedFile? {
        guard case .file(let id) = selection else { return nil }
        return generated?.file(for: id, language: language)
    }

    /// Names the preview highlighter uses so project types colour as types.
    var knownTypeNames: Set<String> { result?.module.typeNames ?? [] }

    // MARK: Navigation

    /// Reveal a diagnostic: switch files if needed, then ask the editor to select it.
    func reveal(_ diagnostic: Diagnostic) {
        guard document[diagnostic.range.file] != nil else { return }
        if case .file(let current) = selection, current != diagnostic.range.file {
            selection = .file(diagnostic.range.file)
        } else if case .settings = selection {
            selection = .file(diagnostic.range.file)
        }
        pendingSelection = diagnostic.range
    }

    // MARK: File operations

    func addFile() {
        let name = document.availableName(basedOn: "Untitled")
        let id = document.appendSource(named: name, text: "")
        hasLocalEdits = true
        selection = .file(id)
    }

    /// - Returns: a message explaining why the rename was refused, or `nil` on success.
    func rename(_ id: SourceFileID, to newName: String) -> String? {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return "The name cannot be empty." }

        let full = trimmed.hasSuffix(".\(ProjectLayout.sourceExtension)")
            ? trimmed
            : "\(trimmed).\(ProjectLayout.sourceExtension)"

        guard document.isNameAvailable(full, excluding: id) else {
            return "“\(full)” is already used in this project."
        }
        document.renameSource(id, to: full)
        hasLocalEdits = true
        return nil
    }

    func delete(_ id: SourceFileID) {
        let wasSelected = selectedSource?.id == id
        document.removeSource(id)
        undoManagers.removeValue(forKey: id)
        hasLocalEdits = true
        if wasSelected {
            selection = document.sources.first.map { Selection.file($0.id) } ?? .settings
        }
    }

    // MARK: Configuration

    func updateConfiguration(_ change: (inout ProjectConfiguration) -> Void) {
        var configuration = document.configuration
        change(&configuration)
        guard configuration != document.configuration else { return }
        document.configuration = configuration
        hasLocalEdits = true
    }

    /// Why Generate is unavailable, or `nil` when it is ready.
    var generationBlocker: String? {
        if fileURL == nil { return "Save the project first" }
        if !configuration.kotlin.isPackageConfigured { return "Set a Kotlin package first" }
        guard let result else { return "Compiling…" }
        if result.hasErrors {
            let count = result.errorCount
            return "Fix \(count) \(count == 1 ? "error" : "errors") first"
        }
        return nil
    }

    var canGenerate: Bool { generationBlocker == nil }

    // MARK: Reloading

    /// The bundle changed on disk.
    ///
    /// With no unsaved edits this reloads silently, so switching git branches under an open
    /// window simply works. With unsaved edits it asks instead — silently replacing
    /// someone's typing is the one unforgivable behaviour here.
    func projectChangedOnDisk() {
        guard let url = fileURL,
              let wrapper = try? FileWrapper(url: url, options: []),
              let onDisk = try? ProjectSnapshot(wrapper: wrapper) else { return }

        guard differs(from: onDisk) else {
            // Disk now matches what is open, which means our own save landed. Clearing
            // the flag here is what stops every later external change from prompting.
            hasLocalEdits = false
            return
        }

        if hasLocalEdits {
            externalChange = ExternalChange(onDisk: onDisk)
        } else {
            adopt(onDisk)
        }
    }

    func acceptExternalChange() {
        guard let change = externalChange else { return }
        externalChange = nil
        adopt(change.onDisk)
    }

    /// Note that something changed that has not been written yet.
    func markEdited() {
        hasLocalEdits = true
    }

    private func adopt(_ snapshot: ProjectSnapshot) {
        Task { [document] in
            // Observing the document is what rebuilds the previews and repairs the
            // selection afterwards.
            try? await document.apply(snapshot: snapshot, previous: nil)
            self.hasLocalEdits = false
        }
    }

    /// Whether what is on disk actually differs from what is open, so a save of our own
    /// does not look like somebody else's edit.
    private func differs(from onDisk: ProjectSnapshot) -> Bool {
        let mine = document.sources.map { "\($0.name)\u{0}\($0.text)" }.sorted()
        let theirs = onDisk.sources.map { "\($0.name)\u{0}\($0.text)" }.sorted()
        return mine != theirs || document.configuration != onDisk.configuration
    }
}

/// What Generate did, for the banner.
struct GenerationReport: Identifiable, Sendable {
    let id = UUID()
    let written: Int
    let unchanged: Int
    let removed: Int
    let destinations: [URL]
    let failure: String?

    var summary: String {
        if let failure { return failure }
        var parts = ["\(written) \(written == 1 ? "file" : "files") written"]
        if unchanged > 0 { parts.append("\(unchanged) unchanged") }
        if removed > 0 { parts.append("\(removed) removed") }
        return parts.joined(separator: ", ")
    }
}

/// The project changed on disk while there were unsaved edits.
struct ExternalChange: Identifiable {
    let id = UUID()
    let onDisk: ProjectSnapshot
}
