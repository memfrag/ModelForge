//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI

/// App-wide settings.
///
/// Emitter configuration is deliberately absent: that is per project and lives in the
/// project's own settings, because two projects open at once will not share a Kotlin
/// package.
struct SettingsWindow: Scene {

    private enum Tabs: Hashable {
        case general
        case editor
        case mcp
    }

    var body: some Scene {
        Settings {
            tabs
                .appEnvironment(.default)
        }
    }
    
    @ViewBuilder var tabs: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
                .tag(Tabs.general)

            EditorSettingsTab()
                .tabItem {
                    Label("Editor", systemImage: "textformat")
                }
                .tag(Tabs.editor)

            MCPSettingsTab()
                .tabItem {
                    Label("Agents", systemImage: "point.3.connected.trianglepath.dotted")
                }
                .tag(Tabs.mcp)
        }
        .frame(width: 500, height: 480)
    }    
}
