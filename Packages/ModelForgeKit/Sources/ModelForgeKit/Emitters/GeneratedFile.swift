import Foundation

public enum Language: String, Sendable, Hashable, CaseIterable {
    case swift
    case kotlin

    public var displayName: String {
        switch self {
        case .swift: "Swift"
        case .kotlin: "Kotlin"
        }
    }

    public var fileExtension: String {
        switch self {
        case .swift: "swift"
        case .kotlin: "kt"
        }
    }
}

/// One file of generated source.
public struct GeneratedFile: Sendable, Hashable, Identifiable {

    /// The file name, for example `User.swift`. Output is one file per `.model` source
    /// file, so this mirrors the name of the file being edited.
    public let name: String
    public let contents: String
    public let language: Language
    /// The `.model` file this was generated from, or `nil` for the shared support file,
    /// which belongs to the project rather than to any one source.
    public let sourceFile: SourceFileID?

    public init(name: String, contents: String, language: Language, sourceFile: SourceFileID?) {
        self.name = name
        self.contents = contents
        self.language = language
        self.sourceFile = sourceFile
    }

    public var id: String { "\(language.rawValue)/\(name)" }
}

/// Everything a project generates.
public struct GeneratedOutput: Sendable, Hashable {

    public let files: [GeneratedFile]

    public init(files: [GeneratedFile]) {
        self.files = files
    }

    public func file(for source: SourceFileID, language: Language) -> GeneratedFile? {
        files.first { $0.sourceFile == source && $0.language == language }
    }

    public func files(for language: Language) -> [GeneratedFile] {
        files.filter { $0.language == language }
    }
}
