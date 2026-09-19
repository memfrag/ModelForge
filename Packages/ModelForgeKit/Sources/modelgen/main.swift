import Foundation
import ModelForgeKit

// A thin wrapper over ModelForgeKit. Everything below is argument handling, reporting and
// exit codes — the compiler and emitters are the same code the app runs, which is the
// point: a schema that builds in the app builds here, and vice versa.

enum ExitCode: Int32 {
    case success = 0
    case schemaProblem = 1
    case usage = 2
}

func fail(_ message: String, code: ExitCode = .usage) -> Never {
    // stdout is buffered and stderr is not, so anything already reported has to be flushed
    // or the failure would print above the detail that explains it.
    fflush(stdout)
    FileHandle.standardError.write(Data(("modelgen: " + message + "\n").utf8))
    exit(code.rawValue)
}

func report(_ message: String, quiet: Bool = false) {
    guard !quiet else { return }
    print(message)
}

// MARK: - Arguments

let arguments: Arguments
do {
    arguments = try Arguments(Array(CommandLine.arguments.dropFirst()))
} catch let error as Arguments.ParseError {
    fail(error.message + "\n\nRun 'modelgen help' for usage.")
} catch {
    fail("\(error)")
}

if arguments.command == .help {
    print(Arguments.usage)
    exit(ExitCode.success.rawValue)
}

// MARK: - The project

let bundle: ProjectBundle
do {
    if let path = arguments.projectPath {
        let expanded = (path as NSString).expandingTildeInPath
        bundle = try ProjectBundle(contentsOf: URL(fileURLWithPath: expanded))
    } else {
        bundle = try ProjectBundle.locate(in: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
    }
} catch let error as ProjectBundle.LoadError {
    if case .notFound = error, arguments.projectPath == nil {
        fail("No .\(ProjectLayout.bundleExtension) project found here. Name one, or run from its folder.")
    }
    fail(error.errorDescription ?? "\(error)")
}

// MARK: - Compile

let result = bundle.compile()
let files = Dictionary(uniqueKeysWithValues: result.files.map { ($0.id, $0) })

if !result.diagnostics.isEmpty {
    // Straight to stderr in the format the app's problems list uses, so a build log reads
    // the same way the editor does.
    FileHandle.standardError.write(Data((DiagnosticRenderer.render(result.diagnostics, in: files) + "\n\n").utf8))
}

switch arguments.command {
case .help:
    break

case .dumpAST:
    guard !result.hasErrors else { fail(result.summary, code: .schemaProblem) }
    for document in result.documents {
        report("// \(files[document.file]?.name ?? "?")", quiet: arguments.isQuiet)
        report(SyntaxDumper.dump(document), quiet: arguments.isQuiet)
    }

case .dumpIR:
    guard !result.hasErrors else { fail(result.summary, code: .schemaProblem) }
    report(IRDumper.dump(result.module), quiet: arguments.isQuiet)

case .format:
    // Formatting needs the file to parse, so a syntax error is reported the same way as
    // anywhere else and nothing is rewritten.
    if result.hasErrors {
        fail("\(bundle.name): \(result.summary)", code: .schemaProblem)
    }

    var reformatted: [String] = []
    for source in bundle.sources {
        guard let formatted = try? SourceFormatter.format(source), formatted != source.text else {
            continue
        }
        reformatted.append(source.name)
        if !arguments.verifiesOnly, !arguments.isDryRun {
            do {
                try formatted.write(to: bundle.url.appendingPathComponent(source.name),
                                    atomically: true, encoding: .utf8)
            } catch {
                fail("could not write \(source.name): \(error.localizedDescription)")
            }
        }
    }

    guard !reformatted.isEmpty else {
        report("\(bundle.name): \(bundle.sources.count) file(s) already formatted", quiet: arguments.isQuiet)
        break
    }

    let pending = arguments.verifiesOnly || arguments.isDryRun
    for name in reformatted {
        report(pending ? "would format \(name)" : "formatted \(name)", quiet: false)
    }
    if arguments.verifiesOnly {
        fail("""
             \(bundle.name): \(reformatted.count) file(s) are not in canonical layout.
             Run 'modelgen format' and commit the result.
             """, code: .schemaProblem)
    }

case .check:
    if result.hasErrors {
        fail("\(bundle.name): \(result.summary)", code: .schemaProblem)
    }
    report("\(bundle.name): \(result.summary) in \(bundle.sources.count) file(s)", quiet: arguments.isQuiet)

case .build:
    if result.hasErrors {
        fail("\(bundle.name): \(result.summary)", code: .schemaProblem)
    }

    let generated = bundle.generate(result)

    func directory(_ override: String?, _ configured: URL?) -> URL? {
        guard let override else { return configured }
        let expanded = (override as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expanded)
    }

    let swiftDirectory = directory(arguments.swiftOutput, bundle.swiftOutputDirectory)
    let kotlinDirectory = directory(arguments.kotlinOutput, bundle.kotlinOutputDirectory)

    guard swiftDirectory != nil || kotlinDirectory != nil else {
        fail("""
             no output folder is configured for \(bundle.name).
             Set one in the app's Project Settings, or pass --swift-output / --kotlin-output.
             """)
    }

    let request = GeneratedFileWriter.Request(
        files: generated.files,
        previousManifest: bundle.manifest,
        swiftDirectory: swiftDirectory,
        kotlinDirectory: kotlinDirectory,
        projectDirectory: bundle.directory)

    if arguments.verifiesOnly || arguments.isDryRun {
        let pending = GeneratedFileWriter.pendingChanges(request)
        guard !pending.isEmpty else {
            report("\(bundle.name): generated code is up to date", quiet: arguments.isQuiet)
            break
        }
        for change in pending {
            report(change, quiet: false)
        }
        if arguments.verifiesOnly {
            fail("""
                 \(bundle.name): generated code is out of date (\(pending.count) file(s)).
                 Run 'modelgen build' and commit the result.
                 """, code: .schemaProblem)
        }
        break
    }

    do {
        let outcome = try GeneratedFileWriter.write(request)
        try bundle.writeManifest(outcome.manifest)

        var parts = ["\(outcome.written) written"]
        if outcome.unchanged > 0 { parts.append("\(outcome.unchanged) unchanged") }
        if outcome.removed > 0 { parts.append("\(outcome.removed) removed") }
        report("\(bundle.name): \(parts.joined(separator: ", "))", quiet: arguments.isQuiet)
    } catch {
        fail(error.localizedDescription)
    }
}

exit(ExitCode.success.rawValue)
