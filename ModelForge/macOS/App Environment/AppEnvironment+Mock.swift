//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation

extension AppEnvironment {

    // MARK: - Mock AppEnvironment

    #if DEBUG
    /// Builds a mock environment configured for development and preview usage.
    ///
    /// Available only in `DEBUG` builds.
    ///
    /// - Returns: A new ``AppEnvironment`` instance with mocked dependencies.
    ///
    internal static func mock() -> AppEnvironment {
        AppEnvironment(
            appSettings: AppSettings.mock(),
            editorTheme: EditorTheme(),
            engineeringMode: EngineeringMode.shared
        )
    }
    #endif
}
