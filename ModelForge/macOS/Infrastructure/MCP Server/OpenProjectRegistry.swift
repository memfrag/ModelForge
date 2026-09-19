//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI

/// The projects currently open in windows.
///
/// A `DocumentGroup` owns its documents privately, so there is no way to enumerate them from
/// outside. Each window registers its session here while it is on screen, which is what lets the
/// embedded MCP server see — and edit — whatever the user has open.
///
/// Registration is keyed by `ObjectIdentifier` rather than by file URL, because an unsaved project
/// has no URL and two windows can briefly share one during a Save As.
@Observable @MainActor final class OpenProjectRegistry {

    private(set) var sessions: [ProjectSession] = []

    func register(_ session: ProjectSession) {
        guard !sessions.contains(where: { $0 === session }) else { return }
        sessions.append(session)
    }

    func deregister(_ session: ProjectSession) {
        sessions.removeAll { $0 === session }
    }

    /// Find a project by name or by path.
    ///
    /// Matching is deliberately forgiving — an agent copies whatever the user says, which is
    /// usually the window title rather than a path.
    func session(matching query: String) throws(MCPToolError) -> ProjectSession {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            throw .invalidArgument("A project name or path is required.")
        }

        if sessions.count == 1, trimmed.isEmpty { return sessions[0] }

        // An exact path wins outright.
        if let byPath = sessions.first(where: { $0.fileURL?.path == trimmed }) {
            return byPath
        }

        let needle = trimmed.lowercased()
        let exact = sessions.filter { $0.projectName.lowercased() == needle }
        if exact.count == 1 { return exact[0] }

        let prefix = sessions.filter { $0.projectName.lowercased().hasPrefix(needle) }
        if prefix.count == 1 { return prefix[0] }
        if prefix.count > 1 {
            throw .ambiguousProject(query: trimmed, matches: prefix.map(\.projectName))
        }

        throw .projectNotFound(query: trimmed, available: sessions.map(\.projectName))
    }
}

extension ProjectSession {

    /// The name shown in the window title, which is what an agent will be told to use.
    var projectName: String {
        fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled"
    }
}
