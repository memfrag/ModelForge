//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI
import SwiftUIToolbox
import AttributionsUI
import AppDesign
import Sparkle

@main
struct MacApp: App {
    
    // swiftlint:disable:next weak_delegate
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) var appDelegate
    
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )
    
    init() {
        AppDesign.apply()
        // Honours the Agents settings: starts the MCP server if it is enabled, and keeps
        // following the toggle and port from then on.
        AppEnvironment.default.mcpServerManager.applyAtLaunch()
    }
    
    var body: some Scene {
        MainWindow(updater: updaterController.updater)
        SettingsWindow()
        AboutWindow(developedBy: "Martin Johannesson",
                    attributionsWindowID: AttributionsWindow.windowID)
        AttributionsWindow([
            ("SwiftUIToolbox", .bsd0Clause(year: "2025", holder: "Apparata AB")),
            ("SensibleStyling", .bsd0Clause(year: "2025", holder: "Apparata AB")),
            ("KeyValueStore", .bsd0Clause(year: "2025", holder: "Apparata AB")),
            ("AttributionsUI", .bsd0Clause(year: "2025", holder: "Apparata AB")),
            ("Sparkle", .mit(year: "2006-2017", holder: "Andy Matuschak et al."))
        ], header: "The following software may be included in this product.")
        HelpWindow()
    }
}
