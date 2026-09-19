import Foundation

/// Everything one compile of a project produced.
public struct CompilationResult: Sendable {

    public let files: [SourceFile]
    public let documents: [DocumentSyntax]
    public let module: Module
    /// Sorted by file, then position, so the problems list is stable between runs.
    public let diagnostics: [Diagnostic]

    public init(files: [SourceFile],
                documents: [DocumentSyntax],
                module: Module,
                diagnostics: [Diagnostic]) {
        self.files = files
        self.documents = documents
        self.module = module
        self.diagnostics = diagnostics
    }

    public var hasErrors: Bool {
        diagnostics.contains { $0.severity == .error }
    }

    public var errorCount: Int {
        diagnostics.count { $0.severity == .error }
    }

    public var warningCount: Int {
        diagnostics.count { $0.severity == .warning }
    }

    public func diagnostics(in file: SourceFileID) -> [Diagnostic] {
        diagnostics.filter { $0.range.file == file }
    }

    public func file(_ id: SourceFileID) -> SourceFile? {
        files.first { $0.id == id }
    }

    public var filesByID: [SourceFileID: SourceFile] {
        Dictionary(uniqueKeysWithValues: files.map { ($0.id, $0) })
    }

    /// The problems in `file` rendered in the terminal caret format, for the Copy action.
    public func renderedDiagnostics(in file: SourceFileID? = nil) -> String {
        let selected = file.map { diagnostics(in: $0) } ?? diagnostics
        return DiagnosticRenderer.render(selected, in: filesByID)
    }

    /// A short summary for the status strip.
    public var summary: String {
        switch (errorCount, warningCount) {
        case (0, 0): "No issues"
        case (let errors, 0): "\(errors) \(errors == 1 ? "error" : "errors")"
        case (0, let warnings): "\(warnings) \(warnings == 1 ? "warning" : "warnings")"
        case (let errors, let warnings):
            "\(errors) \(errors == 1 ? "error" : "errors"), \(warnings) \(warnings == 1 ? "warning" : "warnings")"
        }
    }
}
