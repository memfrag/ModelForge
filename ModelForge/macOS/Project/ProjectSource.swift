//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation
import ModelForgeKit

/// One `.model` file inside a project.
///
/// A value type: the document is a `FileDocument` struct, so editing a source is an
/// ordinary mutation through the document's binding — which is what makes SwiftUI mark the
/// project dirty and autosave it, with nothing to remember to call.
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
