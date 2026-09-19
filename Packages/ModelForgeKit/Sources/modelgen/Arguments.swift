import Foundation
import ModelForgeKit

/// What the user asked for.
///
/// Hand-parsed rather than pulled in from swift-argument-parser: the Kit is deliberately
/// dependency-free so it stays trivial to build in CI, and this is a handful of flags.
struct Arguments {

    enum Command: String, CaseIterable {
        case build
        case check
        case dumpIR = "dump-ir"
        case dumpAST = "dump-ast"
        case help
    }

    var command: Command = .build
    var projectPath: String?
    var swiftOutput: String?
    var kotlinOutput: String?
    /// Report what would change without writing anything.
    var isDryRun = false
    /// Fail when the generated code on disk is out of date, instead of updating it.
    var verifiesOnly = false
    var isQuiet = false

    enum ParseError: Error {
        case unknownOption(String)
        case missingValue(String)
        case unknownCommand(String)

        var message: String {
            switch self {
            case .unknownOption(let option): "Unknown option \(option)."
            case .missingValue(let option): "\(option) needs a value."
            case .unknownCommand(let command): "Unknown command \"\(command)\"."
            }
        }
    }

    init(_ arguments: [String]) throws {
        var rest = arguments

        if let first = rest.first, !first.hasPrefix("-") {
            guard let command = Command(rawValue: first) else {
                throw ParseError.unknownCommand(first)
            }
            self.command = command
            rest.removeFirst()
        }

        var index = 0
        while index < rest.count {
            let argument = rest[index]

            func value() throws -> String {
                guard index + 1 < rest.count else { throw ParseError.missingValue(argument) }
                index += 1
                return rest[index]
            }

            switch argument {
            case "--swift-output": swiftOutput = try value()
            case "--kotlin-output": kotlinOutput = try value()
            case "--dry-run", "-n": isDryRun = true
            case "--verify": verifiesOnly = true
            case "--quiet", "-q": isQuiet = true
            case "--help", "-h": command = .help
            default:
                guard !argument.hasPrefix("-") else {
                    throw ParseError.unknownOption(argument)
                }
                projectPath = argument
            }
            index += 1
        }
    }

    static let usage = """
    modelgen — compile a ModelForge project and generate Swift and Kotlin.

    USAGE
        modelgen [command] [project] [options]

    COMMANDS
        build       Compile and write the generated Swift and Kotlin. The default.
        check       Compile and report problems. Writes nothing.
        dump-ir     Print the normalized intermediate representation.
        dump-ast    Print the syntax tree.
        help        Show this.

    ARGUMENTS
        project     Path to a .modelforge bundle. Defaults to the only one in the
                    current directory.

    OPTIONS
        --swift-output <dir>    Override the Swift output folder from Config.json.
        --kotlin-output <dir>   Override the Kotlin output folder.
        --verify                Fail if the generated code on disk is out of date,
                                rather than updating it. For CI.
        --dry-run, -n           Report what would be written, and write nothing.
        --quiet, -q             Only report problems.
        --help, -h              Show this.

    EXIT STATUS
        0   Success, or no changes needed.
        1   The schema has errors, or --verify found stale output.
        2   The project could not be read, or the arguments made no sense.
    """
}
