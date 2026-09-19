//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation
import ModelForgeKit

/// One `.model` file inside a project.
///
/// A value type, so a project's contents cross to the reader and writer — which run off
/// the main actor — with no locking. Editing one is an ordinary mutation of the document,
/// which is what marks the project dirty and gets it autosaved.
nonisolated struct ProjectSource: Identifiable, Sendable, Hashable {

    /// Stable for as long as the project stays open, so diagnostics and generated output
    /// keep pointing at the same file across renames and edits.
    let id: SourceFileID
    var name: String
    var text: String

    init(id: SourceFileID, name: String, text: String) {
        self.id = id
        self.name = name
        self.text = text
    }

    /// The name shown in the file list, without the extension.
    var displayName: String {
        (name as NSString).deletingPathExtension
    }

    /// The value the compiler works from.
    var sourceFile: SourceFile {
        SourceFile(id: id, name: name, text: text)
    }
}
