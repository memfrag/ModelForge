import Foundation

/// How the Swift emitter should behave.
public struct SwiftEmitterConfiguration: Sendable, Hashable, Codable {

    public enum AccessLevel: String, Sendable, Hashable, Codable, CaseIterable {
        case `internal`
        case `public`

        /// The prefix written before each declaration, including a trailing space.
        var prefix: String {
            self == .public ? "public " : ""
        }
    }

    /// Documentation only — Swift has no per-file module declaration. Kept so the
    /// generated header can name the module the files belong to.
    public var module: String?
    public var accessLevel: AccessLevel
    public var codable: Bool
    public var equatable: Bool
    public var hashable: Bool
    public var sendable: Bool
    /// Output directory, relative to the project bundle unless absolute.
    public var output: String?
    /// Overrides for the default scalar mapping, keyed by DSL type name.
    public var typeMappings: [String: String]

    public init(module: String? = nil,
                accessLevel: AccessLevel = .internal,
                codable: Bool = true,
                equatable: Bool = true,
                hashable: Bool = false,
                sendable: Bool = true,
                output: String? = nil,
                typeMappings: [String: String] = [:]) {
        self.module = module
        self.accessLevel = accessLevel
        self.codable = codable
        self.equatable = equatable
        self.hashable = hashable
        self.sendable = sendable
        self.output = output
        self.typeMappings = typeMappings
    }

    /// The Swift type a DSL scalar becomes.
    ///
    /// `Instant` is a `Date` carrying an ISO-8601 wire format, and the schema's `Date`
    /// becomes the generated `ModelForgeDate`, because Foundation has no date-only type.
    /// Both are coded through the generated support file so they agree with Kotlin.
    public static let defaultTypeMappings: [ScalarType: String] = [
        .string: "String",
        .bool: "Bool",
        .int32: "Int32",
        .int64: "Int64",
        .float: "Float",
        .double: "Double",
        .decimal: "Decimal",
        .uuid: "UUID",
        .url: "URL",
        .date: "ModelForgeDate",
        .instant: "Date",
        .duration: "Duration"
    ]

    public func type(for scalar: ScalarType) -> String {
        typeMappings[scalar.rawValue] ?? Self.defaultTypeMappings[scalar] ?? scalar.rawValue
    }

    // Every key is optional so a hand-trimmed or older Config.json still loads, and a
    // newly added setting does not break files written before it existed.
    private enum CodingKeys: String, CodingKey {
        case module, accessLevel, codable, equatable, hashable, sendable, output, typeMappings
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = SwiftEmitterConfiguration()
        module = try container.decodeIfPresent(String.self, forKey: .module)
        accessLevel = try container.decodeIfPresent(AccessLevel.self, forKey: .accessLevel) ?? defaults.accessLevel
        codable = try container.decodeIfPresent(Bool.self, forKey: .codable) ?? defaults.codable
        equatable = try container.decodeIfPresent(Bool.self, forKey: .equatable) ?? defaults.equatable
        hashable = try container.decodeIfPresent(Bool.self, forKey: .hashable) ?? defaults.hashable
        sendable = try container.decodeIfPresent(Bool.self, forKey: .sendable) ?? defaults.sendable
        output = try container.decodeIfPresent(String.self, forKey: .output)
        typeMappings = try container.decodeIfPresent([String: String].self, forKey: .typeMappings) ?? [:]
    }
}

/// A Kotlin type, plus the opt-in its use requires.
public struct KotlinTypeMapping: Sendable, Hashable, Codable {
    /// Fully qualified, for example `kotlin.uuid.Uuid`.
    public var name: String
    /// An annotation class the file must opt in to, if any.
    public var optIn: String?

    public init(name: String, optIn: String? = nil) {
        self.name = name
        self.optIn = optIn
    }

    /// The name written in the code, with its package stripped.
    public var simpleName: String {
        name.split(separator: ".").last.map(String.init) ?? name
    }

    /// Whether using this type needs an import. Types in `kotlin` and `kotlin.collections`
    /// are imported by default in every Kotlin file.
    public var needsImport: Bool {
        let package = name.split(separator: ".").dropLast().joined(separator: ".")
        return !package.isEmpty && package != "kotlin" && package != "kotlin.collections"
    }
}

/// How the Kotlin emitter should behave.
public struct KotlinEmitterConfiguration: Sendable, Hashable, Codable {

    /// The package every generated file declares.
    ///
    /// One package for the whole project, which follows from the flat namespace: per-file
    /// sub-packages would force cross-file Kotlin imports for types the DSL considers
    /// siblings.
    public var package: String
    /// Output directory, relative to the project bundle unless absolute.
    public var output: String?
    public var typeMappings: [String: KotlinTypeMapping]

    /// What a new project starts with. Generate stays disabled until this is changed, so
    /// nobody ships models in someone else's package by accident.
    public static let placeholderPackage = "com.example.models"

    public init(package: String = KotlinEmitterConfiguration.placeholderPackage,
                output: String? = nil,
                typeMappings: [String: KotlinTypeMapping] = [:]) {
        self.package = package
        self.output = output
        self.typeMappings = typeMappings
    }

    public static let defaultTypeMappings: [ScalarType: KotlinTypeMapping] = [
        .string: .init(name: "kotlin.String"),
        .bool: .init(name: "kotlin.Boolean"),
        .int32: .init(name: "kotlin.Int"),
        .int64: .init(name: "kotlin.Long"),
        .float: .init(name: "kotlin.Float"),
        .double: .init(name: "kotlin.Double"),
        .decimal: .init(name: "java.math.BigDecimal"),
        .uuid: .init(name: "kotlin.uuid.Uuid", optIn: "kotlin.uuid.ExperimentalUuidApi"),
        // No dedicated URL type in the Kotlin standard library. A string round-trips with
        // Swift's URL, which encodes as a string too.
        .url: .init(name: "kotlin.String"),
        // Declared in the generated support file rather than taken from
        // kotlinx-datetime, so a schema adds no dependency the project lacked.
        .date: .init(name: "ModelForgeDate"),
        .instant: .init(name: "kotlin.time.Instant", optIn: "kotlin.time.ExperimentalTime"),
        .duration: .init(name: "kotlin.time.Duration")
    ]

    public func mapping(for scalar: ScalarType) -> KotlinTypeMapping {
        typeMappings[scalar.rawValue]
            ?? Self.defaultTypeMappings[scalar]
            ?? KotlinTypeMapping(name: scalar.rawValue)
    }

    public var isPackageConfigured: Bool {
        !package.isEmpty && package != Self.placeholderPackage
    }

    private enum CodingKeys: String, CodingKey {
        case package, output, typeMappings
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        package = try container.decodeIfPresent(String.self, forKey: .package) ?? Self.placeholderPackage
        output = try container.decodeIfPresent(String.self, forKey: .output)
        typeMappings = try container.decodeIfPresent([String: KotlinTypeMapping].self,
                                                     forKey: .typeMappings) ?? [:]
    }
}

/// Everything in a project's `Config.json`.
///
/// Edited only through the Project Settings form, never as text — which is why it is JSON
/// rather than part of the DSL grammar.
public struct ProjectConfiguration: Sendable, Hashable, Codable {

    /// The current on-disk format. A bundle written by a newer ModelForge is refused
    /// rather than opened and mangled.
    public static let currentFormatVersion = 1

    public var formatVersion: Int
    public var swift: SwiftEmitterConfiguration
    public var kotlin: KotlinEmitterConfiguration

    public init(formatVersion: Int = ProjectConfiguration.currentFormatVersion,
                swift: SwiftEmitterConfiguration = .init(),
                kotlin: KotlinEmitterConfiguration = .init()) {
        self.formatVersion = formatVersion
        self.swift = swift
        self.kotlin = kotlin
    }

    /// The generated-file banner. Fixed rather than configurable: §24 wants output that is
    /// byte-identical given the same input, and a header nobody can vary is one less way
    /// for two machines to disagree.
    public static let generatedFileHeader = "// Generated by ModelForge. Do not edit manually."

    public static let `default` = ProjectConfiguration()

    private enum CodingKeys: String, CodingKey {
        case formatVersion, swift, kotlin
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try container.decodeIfPresent(Int.self, forKey: .formatVersion)
            ?? Self.currentFormatVersion
        swift = try container.decodeIfPresent(SwiftEmitterConfiguration.self, forKey: .swift)
            ?? SwiftEmitterConfiguration()
        kotlin = try container.decodeIfPresent(KotlinEmitterConfiguration.self, forKey: .kotlin)
            ?? KotlinEmitterConfiguration()
    }
}
