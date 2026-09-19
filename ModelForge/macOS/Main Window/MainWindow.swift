//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI
import SwiftUIToolbox
import Sparkle

/// The project window scene.
///
/// A `DocumentGroup` over the `.modelforge` bundle, so Open, Save, Recents, version
/// browsing and the proxy icon all come from macOS rather than being rebuilt.
///
/// Built on the `Document` protocol, whose documents are plain `@Observable` classes —
/// no `ObservableObject`, and no manual change tracking.
struct MainWindow: Scene {

    let updater: SPUUpdater

    var body: some Scene {
        DocumentGroup { document in
            ProjectWindow(document: document,
                          settings: AppEnvironment.default.appSettings)
                .frame(minWidth: 1000, minHeight: 560)
                .appEnvironment(.default)
        } makeDocument: { urlConfiguration, _ in
            // A document with no URL is a brand-new project, which starts from the
            // worked example. An existing one is filled in by `apply(snapshot:previous:)`
            // once the reader has run off the main actor.
            let document = ProjectDocument(
                snapshot: urlConfiguration.fileURL == nil ? .starter : ProjectSnapshot(),
                urlConfiguration: urlConfiguration)
            return document
        }
        .defaultSize(width: 1440, height: 880)
        .commands {
            AboutCommand()
            CheckForUpdatesCommand(updater: updater)
            FileCommands()
            GenerateCommands()
            ViewCommands()
            AlwaysOnTopCommand()
            HelpCommands()
        }
    }
}
