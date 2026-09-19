import Testing
import Foundation
@testable import ModelForgeKit

@Suite("Configuration")
struct ConfigurationTests {

    private func data(_ json: String) -> Data { Data(json.utf8) }

    @Test("round-trips through JSON")
    func roundTrips() throws {
        var configuration = ProjectConfiguration.default
        configuration.kotlin.package = "com.example.app"
        configuration.swift.module = "AppModels"
        configuration.swift.accessLevel = .public

        let encoded = try ConfigurationStore.data(for: configuration, preserving: nil)
        let loaded = try ConfigurationStore.load(from: encoded)
        #expect(loaded.configuration == configuration)
    }

    @Test("keys this version does not understand survive a save")
    func preservesUnknownKeys() throws {
        let original = data("""
        {
          "formatVersion": 1,
          "futureFeature": { "enabled": true },
          "kotlin": { "package": "com.example.app", "futureKotlinKey": 7 },
          "swift": {}
        }
        """)
        let loaded = try ConfigurationStore.load(from: original)
        #expect(loaded.configuration.kotlin.package == "com.example.app")

        let saved = try ConfigurationStore.data(for: loaded.configuration, preserving: loaded.raw)
        let text = String(decoding: saved, as: UTF8.self)
        #expect(text.contains("futureFeature"))
        #expect(text.contains("futureKotlinKey"))
    }

    @Test("a newer format is refused rather than mangled")
    func refusesNewerFormat() {
        let future = data("""
        { "formatVersion": 99, "swift": {}, "kotlin": { "package": "com.example" } }
        """)
        #expect(throws: ConfigurationStore.LoadError.newerFormat(found: 99, supported: 1)) {
            try ConfigurationStore.load(from: future)
        }
    }

    @Test("invalid JSON reports something a person can act on")
    func rejectsInvalidJSON() {
        #expect(throws: ConfigurationStore.LoadError.self) {
            try ConfigurationStore.load(from: data("{ not json"))
        }
    }

    @Test("saving is byte-stable, so the file does not churn in git")
    func savingIsStable() throws {
        let configuration = ProjectConfiguration.default
        let first = try ConfigurationStore.data(for: configuration, preserving: nil)
        let second = try ConfigurationStore.data(for: configuration, preserving: nil)
        #expect(first == second)
    }

    @Test("a new project starts with the placeholder package and is not ready to generate")
    func placeholderBlocksGeneration() {
        #expect(ProjectConfiguration.default.kotlin.isPackageConfigured == false)
        var configured = ProjectConfiguration.default
        configured.kotlin.package = "com.example.app"
        #expect(configured.kotlin.isPackageConfigured)
    }
}
