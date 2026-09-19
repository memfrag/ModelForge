//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation
import UniformTypeIdentifiers
import ModelForgeKit

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
