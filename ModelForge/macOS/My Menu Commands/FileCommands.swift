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

        CommandGroup(after: .pasteboard) {
            Button("Format Model Files") {
                session?.formatAllFiles()
            }
            .keyboardShortcut("f", modifiers: [.command, .control])
            .disabled(session?.hasUnformattedFiles != true)
        }
    }
}

/// View-menu items for the preview column.
struct ViewCommands: Commands {

    @FocusedValue(\.projectSession) private var session

    private var settings: AppSettings { AppEnvironment.default.appSettings }

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Section {
                Button("Show Swift") {
                    settings.previewLayout = .single
                    session?.previewLanguage = .swift
                }
                .keyboardShortcut("1", modifiers: [.command, .control])
                .disabled(session == nil)

                Button("Show Kotlin") {
                    settings.previewLayout = .single
                    session?.previewLanguage = .kotlin
                }
                .keyboardShortcut("2", modifiers: [.command, .control])
                .disabled(session == nil)

                Button("Show Both") {
                    settings.previewLayout = .both
                }
                .keyboardShortcut("3", modifiers: [.command, .control])
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
