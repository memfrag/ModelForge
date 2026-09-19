//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI

/// File-menu items that act on the focused project's files.
struct FileCommands: Commands {

    @FocusedValue(\.projectSession) private var session

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("New Model File") {
                session?.addFile()
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .disabled(session == nil)
        }
    }
}

/// View-menu items for the preview column.
struct ViewCommands: Commands {

    @FocusedValue(\.projectSession) private var session

    @AppStorage("settings.preview.layout") private var layoutRaw = PreviewLayout.single.rawValue

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Section {
                Button("Show Swift") {
                    session?.previewLanguage = .swift
                }
                .keyboardShortcut("1", modifiers: [.command, .control])
                .disabled(session == nil)

                Button("Show Kotlin") {
                    session?.previewLanguage = .kotlin
                }
                .keyboardShortcut("2", modifiers: [.command, .control])
                .disabled(session == nil)
            }

            Section {
                Button("Toggle Problems") {
                    session?.isProblemsListExpanded.toggle()
                }
                .keyboardShortcut("y", modifiers: [.command, .shift])
                .disabled(session?.diagnostics.isEmpty != false)
            }
        }
    }
}
