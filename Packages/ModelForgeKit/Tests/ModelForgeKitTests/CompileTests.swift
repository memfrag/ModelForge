import Testing
import Foundation
@testable import ModelForgeKit

/// Compiles the generated Swift for real.
///
/// This is the class of bug the rest of the suite cannot catch: output that looks
/// plausible and is not valid on the target platform. Gated behind an environment variable
/// because it shells out to the compiler and takes seconds rather than milliseconds.
///
///     MODELFORGE_COMPILE_TESTS=1 swift test --filter Compilation
///
/// There is no Kotlin equivalent here — `kotlinc` plus the serialization plugin is too
/// heavy for a unit suite. `scripts/verify-kotlin-fixtures.sh` covers that before a release.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["MODELFORGE_COMPILE_TESTS"] == "1"))
struct CompilationTests {

    @Test("every generated Swift fixture type-checks")
    func generatedSwiftTypeChecks() throws {
        let expected = Snapshot.fixturesDirectory()
            .appendingPathComponent("Generation/EndToEnd/expected")
        let swiftFiles = try FileManager.default
            .contentsOfDirectory(at: expected, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }

        try #require(!swiftFiles.isEmpty)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        // Swift 6 language mode on purpose. Without it this checks Swift 5 rules, and the
        // generated code lands in packages that are built as Swift 6 — which is how a
        // support file holding a non-`Sendable` formatter in a `static let` passed here
        // and failed in a real project.
        process.arguments = ["swiftc", "-typecheck", "-parse-as-library", "-swift-version", "6"]
            + swiftFiles.map(\.path)

        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = Pipe()
        try process.run()
        let output = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()

        #expect(process.terminationStatus == 0, "swiftc rejected the generated code:\n\(output)")
    }
}
