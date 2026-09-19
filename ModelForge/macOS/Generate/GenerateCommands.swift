//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI

/// File ▸ Generate.
///
/// Keeps ⌘B, which the boilerplate used for its example Build command and which is what
/// muscle memory reaches for in a code-generating tool.
struct GenerateCommands: Commands {

    @FocusedValue(\.projectSession) private var session

    var body: some Commands {
        CommandGroup(after: .saveItem) {
            Section {
                Button(title) {
                    session?.generate()
                }
                .keyboardShortcut("b", modifiers: [.command])
                .disabled(session?.canGenerate != true)

                Button("Reveal Output in Finder") {
                    session?.revealOutput()
                }
                .disabled(session?.hasOutputDirectories != true)
            }
        }
    }

    /// The menu item says why it is disabled rather than leaving you guessing.
    private var title: String {
        guard let session else { return "Generate" }
        if let blocker = session.generationBlocker {
            return "Generate (\(blocker))"
        }
        return "Generate"
    }
}

/// Lets the menu bar reach the focused window's session.
struct ProjectSessionFocusedValueKey: FocusedValueKey {
    typealias Value = ProjectSession
}

extension FocusedValues {
    var projectSession: ProjectSession? {
        get { self[ProjectSessionFocusedValueKey.self] }
        set { self[ProjectSessionFocusedValueKey.self] = newValue }
    }
}
