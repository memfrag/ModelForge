//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation

/// Where generated files go.
///
/// Output paths are stored **relative to the project bundle**, so they survive a rename,
/// keep working for anyone else who clones the repository, and mean the same thing to a
/// future command-line build. An absolute path is accepted and stored as-is for one-off
/// use.
nonisolated enum OutputLocation {

    /// Turn a chosen folder into the path to store in `Config.json`.
    static func relativePath(from base: URL?, to target: URL) -> String {
        guard let base else { return target.path }

        let baseComponents = base.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        let targetComponents = target.standardizedFileURL.resolvingSymlinksInPath().pathComponents

        var shared = 0
        while shared < baseComponents.count,
              shared < targetComponents.count,
              baseComponents[shared] == targetComponents[shared] {
            shared += 1
        }

        // Nothing in common at all means different volumes; an absolute path is the only
        // thing that can be right.
        guard shared > 1 else { return target.path }

        let ascend = Array(repeating: "..", count: baseComponents.count - shared)
        let descend = targetComponents[shared...]
        let components = ascend + descend
        return components.isEmpty ? "." : components.joined(separator: "/")
    }

    /// Resolve a stored path against the project bundle.
    static func resolve(_ path: String, relativeTo base: URL?) -> URL? {
        guard !path.isEmpty else { return nil }
        if path.hasPrefix("/") { return URL(fileURLWithPath: path) }
        if path.hasPrefix("~") {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        }
        guard let base else { return nil }
        return URL(fileURLWithPath: path, relativeTo: base).standardizedFileURL
    }
}
