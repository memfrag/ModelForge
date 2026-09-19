import Foundation
@testable import ModelForgeKit

enum ParseSupport {

    struct Result {
        let file: SourceFile
        let document: DocumentSyntax
        let diagnostics: [Diagnostic]

        var codes: [DiagnosticCode] { diagnostics.map(\.code) }

        /// Diagnostics as `line:column code` — compact enough to assert on directly.
        var positions: [String] {
            diagnostics.map { "\($0.range.start.line):\($0.range.start.column) \($0.code.rawValue)" }
        }

        var declarationNames: [String] {
            document.declarations.map(\.name.text)
        }

        var rendered: String {
            DiagnosticRenderer.render(diagnostics, in: [file.id: file])
        }

        var dump: String {
            SyntaxDumper.dump(document)
        }
    }

    static func parse(_ source: String, name: String = "test.model") -> Result {
        let file = SourceFile(id: SourceFileID(0), name: name, text: source)
        var bag = DiagnosticBag()
        let document = Parser.parse(file, diagnostics: &bag)
        return Result(file: file, document: document, diagnostics: bag.sorted())
    }

    static func model(_ result: Result, named name: String) -> ModelSyntax? {
        for declaration in result.document.declarations {
            if case .model(let model) = declaration, model.name.text == name { return model }
        }
        return nil
    }
}

enum AnalyzeSupport {

    struct Result {
        let files: [SourceFile]
        let module: Module
        let diagnostics: [Diagnostic]

        var codes: [DiagnosticCode] { diagnostics.map(\.code) }
        var errors: [Diagnostic] { diagnostics.filter { $0.severity == .error } }
        var warnings: [Diagnostic] { diagnostics.filter { $0.severity == .warning } }
        var messages: [String] { diagnostics.map(\.message) }
        var helps: [String] { diagnostics.flatMap { $0.notes.map(\.message) } }

        var rendered: String {
            DiagnosticRenderer.render(diagnostics,
                                      in: Dictionary(uniqueKeysWithValues: files.map { ($0.id, $0) }))
        }

        var dump: String { IRDumper.dump(module) }

        func model(_ name: String) -> ModelDefinition? {
            if case .model(let model)? = module[name] { return model }
            return nil
        }

        func union(_ name: String) -> UnionDefinition? {
            if case .union(let union)? = module[name] { return union }
            return nil
        }
    }

    /// Analyse a whole project. Files are given as `(name, source)` pairs; they share one
    /// flat namespace, exactly as the files inside a bundle do.
    static func analyze(_ sources: [(name: String, text: String)]) -> Result {
        var bag = DiagnosticBag()
        var files: [SourceFile] = []
        var documents: [DocumentSyntax] = []

        for (index, source) in sources.enumerated() {
            let file = SourceFile(id: SourceFileID(index), name: source.name, text: source.text)
            files.append(file)
            documents.append(Parser.parse(file, diagnostics: &bag))
        }

        let module = SemanticAnalyzer.analyze(documents, diagnostics: &bag)
        return Result(files: files, module: module, diagnostics: bag.sorted())
    }

    static func analyze(_ source: String) -> Result {
        analyze([(name: "test.model", text: source)])
    }
}
