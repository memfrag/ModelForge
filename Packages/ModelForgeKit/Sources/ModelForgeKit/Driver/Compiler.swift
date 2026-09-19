import Foundation

/// Compiles a whole project in one pass.
///
/// Pure and synchronous, with no isolation of its own, so the app can hand it a snapshot
/// of its editors and run it off the main actor without any locking.
///
/// The unit of compilation is the whole project rather than a single file: a bundle's
/// `.model` files share one flat namespace. At the sizes this tool targets — tens of files
/// and hundreds of declarations — a full recompile takes about a millisecond, which is why
/// there is no incremental machinery here to get wrong.
public enum Compiler {

    public static func compile(_ files: [SourceFile]) -> CompilationResult {
        var diagnostics = DiagnosticBag()
        var documents: [DocumentSyntax] = []

        for file in files {
            documents.append(Parser.parse(file, diagnostics: &diagnostics))
        }

        let module = SemanticAnalyzer.analyze(documents, diagnostics: &diagnostics)

        return CompilationResult(files: files,
                                 documents: documents,
                                 module: module,
                                 diagnostics: diagnostics.sorted())
    }
}

/// Emits source for every file in a project.
public enum Generator {

    /// Generate both languages for every source file.
    ///
    /// Always the whole project, never one file: the generated output mirrors the project
    /// exactly, and Generate relies on that to work out which previously written files are
    /// now stale.
    public static func generate(_ result: CompilationResult,
                                configuration: ProjectConfiguration) -> GeneratedOutput {
        let swift = SwiftEmitter(configuration: configuration.swift)
        let kotlin = KotlinEmitter(configuration: configuration.kotlin)

        var generated: [GeneratedFile] = []
        for file in result.files {
            generated.append(swift.emit(file: file.id, named: file.name, from: result.module))
            generated.append(kotlin.emit(file: file.id, named: file.name, from: result.module))
        }

        // One support file per language, holding the coders that make the two platforms
        // agree on the scalars neither codes compatibly on its own.
        generated.append(GeneratedFile(name: "\(SupportFile.baseName).swift",
                                       contents: SupportFile.swift(configuration: configuration.swift),
                                       language: .swift,
                                       sourceFile: nil))
        generated.append(GeneratedFile(name: "\(SupportFile.baseName).kt",
                                       contents: SupportFile.kotlin(configuration: configuration.kotlin),
                                       language: .kotlin,
                                       sourceFile: nil))

        return GeneratedOutput(files: generated)
    }
}

/// One compile plus one generate, which is what a debounce tick runs.
public enum CompilePipeline {

    public struct Output: Sendable {
        public let result: CompilationResult
        public let generated: GeneratedOutput

        public init(result: CompilationResult, generated: GeneratedOutput) {
            self.result = result
            self.generated = generated
        }
    }

    public static func run(files: [SourceFile],
                           configuration: ProjectConfiguration) -> Output {
        let result = Compiler.compile(files)
        return Output(result: result,
                      generated: Generator.generate(result, configuration: configuration))
    }
}
