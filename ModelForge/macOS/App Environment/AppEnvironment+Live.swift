//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation

extension AppEnvironment {

    // MARK: - Live AppEnvironment

    /// Builds a live environment configured for production behavior.
    ///
    /// Intended only for ``#Preview`` usage and tests where an explicit instance is required.
    /// Most code should access ``shared`` instead.
    ///
    /// - Returns: A new ``AppEnvironment`` instance with live dependencies.
    ///
    internal static func live() -> AppEnvironment {
        AppEnvironment(
            appSettings: AppSettings(),
            editorTheme: EditorTheme(),
            engineeringMode: EngineeringMode.shared
        )
    }
}
