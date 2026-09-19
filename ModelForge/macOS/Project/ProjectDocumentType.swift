//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation
import UniformTypeIdentifiers

extension UTType {

    /// A ModelForge project: a file package holding the project's `.model` files, its
    /// `Config.json` and the manifest of what it last generated.
    ///
    /// A package rather than a flat file because a project is several sources plus shared
    /// configuration, and they have to travel together. The `.model` files inside stay
    /// plain UTF-8 text, so `grep`, `git diff` and someone else's editor all still work —
    /// the bundle is a container, not an encoding.
    nonisolated static let modelForgeProject = UTType(exportedAs: "pizza.martin.modelforge.project")
}

nonisolated enum ProjectLayout {

    /// Extension of the project bundle itself.
    static let bundleExtension = "modelforge"

    /// Extension of the source files inside it.
    static let sourceExtension = "model"

    static let configurationFileName = "Config.json"
    static let manifestFileName = "Manifest.json"

    /// Files the bundle owns that are not editable sources.
    static let reservedFileNames: Set<String> = [configurationFileName, manifestFileName]

    static func isSourceFile(_ name: String) -> Bool {
        name.hasSuffix(".\(sourceExtension)") && !name.hasPrefix(".")
    }

    /// What a brand-new project contains.
    ///
    /// One example file rather than an empty project, so both previews are populated the
    /// moment a window opens and the language teaches itself.
    static let starterFileName = "Models.model"

    static let starterSource = """
    // Welcome to ModelForge.
    //
    // Define your shared data models here and the Swift and Kotlin panes will
    // keep up as you type. Every .model file in this project shares one
    // namespace, so types can refer to each other without any imports.

    /// A registered user of the application.
    model User {
        /// Stable, server-issued identifier.
        @json("user_id")
        id: UUID

        name: String
        email: String?

        status: UserStatus = .active
        createdAt: Instant
    }

    /// Where an account stands right now.
    enum UserStatus {
        active
        suspended
        deleted
    }

    """
}
