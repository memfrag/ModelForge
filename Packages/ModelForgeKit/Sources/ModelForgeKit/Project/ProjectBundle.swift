import Foundation

/// A ModelForge project read straight off the filesystem.
///
/// The app reads the same layout through a `FileWrapper`, because that is what the document
/// machinery hands it. This is the plain-filesystem path the command-line tool uses, so a
/// schema behaves identically in CI and on screen.
public struct ProjectBundle: Sendable {

    public enum LoadError: Error, LocalizedError, Equatable {
        case notFound(path: String)
        case notABundle(path: String)
        case unreadableConfiguration(String)
        case newerFormat(found: Int, supported: Int)
        case unreadableSource(name: String)

        public var errorDescription: String? {
            switch self {
            case .notFound(let path):
                "No such project: \(path)"
            case .notABundle(let path):
                "\(path) is not a .\(ProjectLayout.bundleExtension) project."
            case .unreadableConfiguration(let detail):
                "\(ProjectLayout.configurationFileName) could not be read. \(detail)"
            case .newerFormat(let found, let supported):
                """
                This project uses format \(found), and this version understands \(supported). \
                Update ModelForge.
                """
            case .unreadableSource(let name):
                "\(name) is not valid UTF-8."
            }
        }
    }

    /// Where the bundle lives. Output paths in the configuration resolve against its parent.
    public let url: URL
    public let sources: [SourceFile]
    public let configuration: ProjectConfiguration
    public let manifest: GenerationManifest

    /// The directory output paths are relative to: the folder containing the bundle.
    public var directory: URL {
        url.deletingLastPathComponent()
    }

    public var name: String {
        url.deletingPathExtension().lastPathComponent
    }

    // MARK: Loading

    public init(contentsOf url: URL) throws(LoadError) {
        let manager = FileManager.default
        var isDirectory: ObjCBool = false

        guard manager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw .notFound(path: url.path)
        }
        guard url.pathExtension == ProjectLayout.bundleExtension else {
            throw .notABundle(path: url.path)
        }

        var configuration = ProjectConfiguration.default
        let configurationURL = url.appendingPathComponent(ProjectLayout.configurationFileName)
        if let data = try? Data(contentsOf: configurationURL) {
            do {
                configuration = try ConfigurationStore.load(from: data).configuration
            } catch let error as ConfigurationStore.LoadError {
                switch error {
                case .newerFormat(let found, let supported):
                    throw .newerFormat(found: found, supported: supported)
                case .unreadable(let detail):
                    throw .unreadableConfiguration(detail)
                }
            } catch {
                throw .unreadableConfiguration("\(error)")
            }
        }

        var manifest = GenerationManifest()
        if let data = try? Data(contentsOf: url.appendingPathComponent(ProjectLayout.manifestFileName)) {
            manifest = GenerationManifest.decoded(from: data)
        }

        // Sorted, so file ids — and therefore the order of generated output — match what
        // the app produces for the same project.
        let names = ((try? manager.contentsOfDirectory(atPath: url.path)) ?? [])
            .filter(ProjectLayout.isSourceFile)
            .sorted()

        var sources: [SourceFile] = []
        for name in names {
            guard let data = try? Data(contentsOf: url.appendingPathComponent(name)),
                  let text = String(data: data, encoding: .utf8) else {
                throw .unreadableSource(name: name)
            }
            sources.append(SourceFile(id: SourceFileID(sources.count), name: name, text: text))
        }

        self.url = url
        self.sources = sources
        self.configuration = configuration
        self.manifest = manifest
    }

    /// Find the single project in a directory.
    ///
    /// Lets the tool be run from a repository root with no arguments, which is how it will
    /// usually be invoked from a build script.
    public static func locate(in directory: URL) throws(LoadError) -> ProjectBundle {
        let candidates = ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
            .filter { $0.hasSuffix(".\(ProjectLayout.bundleExtension)") }
            .sorted()

        guard let only = candidates.first, candidates.count == 1 else {
            throw .notFound(path: directory.path)
        }
        return try ProjectBundle(contentsOf: directory.appendingPathComponent(only))
    }

    // MARK: Using

    public func compile() -> CompilationResult {
        Compiler.compile(sources)
    }

    public func generate(_ result: CompilationResult) -> GeneratedOutput {
        Generator.generate(result, configuration: configuration)
    }

    public var swiftOutputDirectory: URL? {
        configuration.swift.output.flatMap { OutputLocation.resolve($0, relativeTo: directory) }
    }

    public var kotlinOutputDirectory: URL? {
        configuration.kotlin.output.flatMap { OutputLocation.resolve($0, relativeTo: directory) }
    }

    /// Persist the record of what was written, so the next run knows what became stale.
    public func writeManifest(_ manifest: GenerationManifest) throws {
        let url = url.appendingPathComponent(ProjectLayout.manifestFileName)
        if manifest.isEmpty {
            try? FileManager.default.removeItem(at: url)
            return
        }
        try manifest.encoded().write(to: url, options: .atomic)
    }
}
