import Foundation

/// Reads and writes a project's `Config.json`.
///
/// Two things matter here beyond plain `Codable`:
///
/// - **Refusing the future.** A bundle written by a newer ModelForge is rejected rather
///   than opened with its unknown settings quietly ignored. The `.model` files are plain
///   text and never at risk, so the worst outcome is updating the app.
/// - **Preserving what it does not understand.** Unknown keys are kept and written back,
///   so opening a project in an older version and saving it does not strip settings a
///   newer version added.
public enum ConfigurationStore {

    public enum LoadError: Error, Sendable, Equatable {
        /// Written by a newer ModelForge than this one.
        case newerFormat(found: Int, supported: Int)
        case unreadable(String)
    }

    public struct Loaded: Sendable, Hashable {
        public var configuration: ProjectConfiguration
        /// The file exactly as it was read, so unknown keys survive a save.
        public var raw: JSONValue

        public init(configuration: ProjectConfiguration, raw: JSONValue) {
            self.configuration = configuration
            self.raw = raw
        }
    }

    public static func load(from data: Data) throws(LoadError) -> Loaded {
        let raw: JSONValue
        do {
            raw = try JSONDecoder().decode(JSONValue.self, from: data)
        } catch {
            throw .unreadable("Config.json is not valid JSON.")
        }

        let version = version(in: raw)
        guard version <= ProjectConfiguration.currentFormatVersion else {
            throw .newerFormat(found: version, supported: ProjectConfiguration.currentFormatVersion)
        }

        let migrated = migrate(raw, from: version)

        do {
            let encoded = try JSONEncoder().encode(migrated)
            var configuration = try JSONDecoder().decode(ProjectConfiguration.self, from: encoded)
            configuration.formatVersion = ProjectConfiguration.currentFormatVersion
            return Loaded(configuration: configuration, raw: migrated)
        } catch {
            throw .unreadable("Config.json is missing something required, or has a value of the wrong type.")
        }
    }

    /// Encode for writing, keeping any keys the original had that this version does not
    /// know about.
    public static func data(for configuration: ProjectConfiguration,
                            preserving raw: JSONValue?) throws -> Data {
        let encoder = JSONEncoder()
        // Sorted keys and fixed formatting: two machines saving the same settings must
        // produce the same bytes, or the file churns in git for no reason.
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

        guard let raw else {
            return try encoder.encode(configuration)
        }

        let encoded = try JSONEncoder().encode(configuration)
        let known = try JSONDecoder().decode(JSONValue.self, from: encoded)
        return try encoder.encode(raw.deepMerging(known))
    }

    // MARK: Versioning

    private static func version(in raw: JSONValue) -> Int {
        guard case .number(let value)? = raw.object?["formatVersion"] else {
            // A file with no version predates versioning, so treat it as the first.
            return 1
        }
        return Int(value)
    }

    /// Bring an older file up to the current shape.
    ///
    /// Version 1 is the first format, so there is nothing to do yet. Each future bump adds
    /// one step here, and `ConfigurationTests` pins the behaviour.
    private static func migrate(_ raw: JSONValue, from version: Int) -> JSONValue {
        var current = raw

        // Each future format bump adds one step here, guarded by the version it upgrades
        // from. Version 1 is the first format, so there is nothing to do yet.
        _ = version

        if case .object(var object) = current {
            object["formatVersion"] = .number(Double(ProjectConfiguration.currentFormatVersion))
            current = .object(object)
        }
        return current
    }
}
