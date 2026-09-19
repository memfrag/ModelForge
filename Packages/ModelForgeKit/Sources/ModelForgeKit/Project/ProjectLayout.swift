import Foundation

/// How a ModelForge project is laid out on disk.
///
/// Shared by the app and the `modelgen` command-line tool, which have to agree about it
/// exactly: one reads the bundle through a `FileWrapper`, the other straight off the
/// filesystem, and a disagreement would show up as a project that builds differently in CI
/// than it does on screen.
public enum ProjectLayout {

    /// Extension of the project bundle itself.
    public static let bundleExtension = "modelforge"

    /// Extension of the source files inside it.
    public static let sourceExtension = "model"

    public static let configurationFileName = "Config.json"
    public static let manifestFileName = "Manifest.json"

    /// Files the bundle owns that are not editable sources.
    public static let reservedFileNames: Set<String> = [configurationFileName, manifestFileName]

    public static func isSourceFile(_ name: String) -> Bool {
        name.hasSuffix(".\(sourceExtension)") && !name.hasPrefix(".")
    }

    /// What a brand-new project contains. See ``StarterDocument``.
    public static var starterFileName: String { StarterDocument.fileName }

    public static var starterSource: String { StarterDocument.source }
}
