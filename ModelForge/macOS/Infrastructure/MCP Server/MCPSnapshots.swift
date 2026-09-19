//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation
import ModelForgeKit

// JSON shapes returned by the MCP tools. Plain values, so they cross from the main actor to the
// NIO event loop without ceremony, and deliberately agent-facing: they carry the *derived* facts
// an agent would otherwise have to work out, such as why generation is unavailable.

nonisolated struct MCPProjectSnapshot: Codable, Sendable {
    var name: String
    /// `nil` for a project that has never been saved; such a project cannot generate.
    var path: String?
    var modelFiles: [String]
    var errorCount: Int
    var warningCount: Int
    var kotlinPackage: String
    var swiftOutput: String?
    var kotlinOutput: String?
    var canGenerate: Bool
    /// Why `canGenerate` is false, phrased as the thing to fix.
    var generationBlocker: String?
}

nonisolated struct ModelFileSnapshot: Codable, Sendable {
    var name: String
    var lineCount: Int
    var errorCount: Int
    var warningCount: Int
    /// The types this file declares, in source order.
    var declares: [String]
}

nonisolated struct DiagnosticSnapshot: Codable, Sendable {
    var file: String
    var line: Int
    var column: Int
    var severity: String
    /// A stable identifier for the kind of problem, such as `unknownType`.
    var code: String
    var message: String
    /// Suggestions attached to the problem, such as "did you mean 'User'?".
    var help: [String]
}

nonisolated struct CompileSnapshot: Codable, Sendable {
    var ok: Bool
    var errorCount: Int
    var warningCount: Int
    var diagnostics: [DiagnosticSnapshot]
    /// The problems rendered with source excerpts and carets, as the CLI would print them.
    /// Omitted when there are none.
    var rendered: String?
}

nonisolated struct GeneratedCodeSnapshot: Codable, Sendable {
    var name: String
    var language: String
    /// The `.model` file this came from, or `nil` for the shared support file.
    var from: String?
    var contents: String
}

nonisolated struct GenerationSnapshot: Codable, Sendable {
    var written: Int
    var unchanged: Int
    var removed: Int
    var swiftOutput: String?
    var kotlinOutput: String?
}

nonisolated struct ConfigurationSnapshot: Codable, Sendable {
    var kotlinPackage: String
    var kotlinOutput: String?
    var swiftModule: String?
    var swiftOutput: String?
    var swiftAccessLevel: String
    var codable: Bool
    var equatable: Bool
    var hashable: Bool
    var sendable: Bool
}

nonisolated enum MCPJSON {

    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    /// Encodes a snapshot to a compact JSON string, for use as tool-call text output.
    static func string(_ value: some Encodable) -> String {
        guard let data = try? makeEncoder().encode(value),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }
}

// MARK: - Building snapshots from a compile

extension DiagnosticSnapshot {

    init(_ diagnostic: Diagnostic, fileName: String) {
        self.init(file: fileName,
                  line: diagnostic.range.start.line,
                  column: diagnostic.range.start.column,
                  severity: diagnostic.severity.label,
                  code: diagnostic.code.rawValue,
                  message: diagnostic.message,
                  help: diagnostic.notes.map(\.message))
    }
}

extension CompileSnapshot {

    /// - Parameter file: when given, only that file's problems are reported, though the whole
    ///   project is still compiled — the cause of a problem is often in another file.
    init(_ result: CompilationResult, limitedTo file: SourceFileID? = nil) {
        let selected = file.map { result.diagnostics(in: $0) } ?? result.diagnostics
        let names = Dictionary(uniqueKeysWithValues: result.files.map { ($0.id, $0.name) })

        self.init(ok: !result.hasErrors,
                  errorCount: selected.count { $0.severity == .error },
                  warningCount: selected.count { $0.severity == .warning },
                  diagnostics: selected.map {
                      DiagnosticSnapshot($0, fileName: names[$0.range.file] ?? "?")
                  },
                  rendered: selected.isEmpty
                      ? nil
                      : DiagnosticRenderer.render(selected, in: result.filesByID))
    }
}
