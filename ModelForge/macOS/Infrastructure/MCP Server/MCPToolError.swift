//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation

/// Errors surfaced to an MCP client as a tool-call failure (`isError: true` with a text message).
///
/// The message is the only thing the model sees, so each one says what went wrong *and* what to do
/// next — listing the available projects, naming the blocker, pointing at the tool that fixes it.
nonisolated enum MCPToolError: Error, Sendable {
    case projectNotFound(query: String, available: [String])
    case ambiguousProject(query: String, matches: [String])
    case fileNotFound(project: String, query: String, available: [String])
    case fileAlreadyExists(String)
    case invalidArgument(String)
    case cannotGenerate(reason: String)
    case noOutputConfigured
    case openFailed(path: String, reason: String)

    var message: String {
        switch self {
        case .projectNotFound(let query, let available):
            let list = available.isEmpty
                ? "No projects are open. Use open_project with the path to a .modelforge bundle."
                : "Open projects: \(available.joined(separator: ", "))."
            return "No open project matches \"\(query)\". \(list)"

        case .ambiguousProject(let query, let matches):
            return "\"\(query)\" matches several open projects: \(matches.joined(separator: ", ")). Use the full name or the bundle's path."

        case .fileNotFound(let project, let query, let available):
            let list = available.isEmpty
                ? "It has no model files yet."
                : "Its files are: \(available.joined(separator: ", "))."
            return "No model file matching \"\(query)\" in project \"\(project)\". \(list)"

        case .fileAlreadyExists(let name):
            return "\"\(name)\" already exists in this project. Use write_model_file to replace its contents, or pick another name."

        case .invalidArgument(let detail):
            return detail

        case .cannotGenerate(let reason):
            return "Cannot generate: \(reason). Fix that first, then call generate again."

        case .noOutputConfigured:
            return "No output folder is set for this project. Set swift_output and/or kotlin_output with set_configuration first — paths are relative to the .modelforge bundle."

        case .openFailed(let path, let reason):
            return "Could not open \"\(path)\": \(reason)"
        }
    }
}
