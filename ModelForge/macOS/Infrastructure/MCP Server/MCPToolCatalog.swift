//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation
import MCP

/// The tools ModelForge exposes over MCP.
///
/// Descriptions are prompt engineering: each one says when to reach for the tool and what it will
/// refuse to do, so the model picks the right one without trial and error.
nonisolated enum MCPToolCatalog {

    private static let project: Value = [
        "type": "string",
        "description": "Project name as shown in the window title, or the path to its .modelforge bundle. Omit nothing — use list_projects if unsure."
    ]

    private static let file: Value = [
        "type": "string",
        "description": "Model file name, with or without the .model extension."
    ]

    static let tools: [Tool] = [
        Tool(
            name: "list_projects",
            description: "List the ModelForge projects currently open, with their model files, problem counts and whether they are ready to generate. Start here.",
            inputSchema: .object(["type": "object", "properties": .object([:])])
        ),

        Tool(
            name: "open_project",
            description: "Open a .modelforge project bundle in a new window so the other tools can reach it.",
            inputSchema: .object([
                "type": "object",
                "properties": [
                    "path": ["type": "string", "description": "Path to a .modelforge bundle."]
                ],
                "required": ["path"]
            ])
        ),

        Tool(
            name: "list_model_files",
            description: "List a project's .model files with the types each one declares and its problem counts.",
            inputSchema: .object([
                "type": "object",
                "properties": ["project": project],
                "required": ["project"]
            ])
        ),

        Tool(
            name: "read_model_file",
            description: "Read a model file's DSL source.",
            inputSchema: .object([
                "type": "object",
                "properties": ["project": project, "file": file],
                "required": ["project", "file"]
            ])
        ),

        Tool(
            name: "check_model_source",
            description: "Compile a candidate version of a file WITHOUT saving it, and return the problems. The rest of the project is included, so cross-file references resolve exactly as they would after a write. Use this before write_model_file when you are unsure of the syntax.",
            inputSchema: .object([
                "type": "object",
                "properties": [
                    "project": project,
                    "file": file,
                    "source": ["type": "string", "description": "The full DSL source to check."]
                ],
                "required": ["project", "file", "source"]
            ])
        ),

        Tool(
            name: "write_model_file",
            description: "Replace a model file's entire contents, creating the file if it does not exist. Returns the problems for the whole project afterwards, since one file's change routinely breaks or fixes another. The change appears in the open window immediately but is not written to disk until the document is saved.",
            inputSchema: .object([
                "type": "object",
                "properties": [
                    "project": project,
                    "file": file,
                    "source": ["type": "string", "description": "The full DSL source. This replaces the file, so include everything you want to keep."]
                ],
                "required": ["project", "file", "source"]
            ])
        ),

        Tool(
            name: "rename_model_file",
            description: "Rename a model file. The files it generates are renamed to match on the next generate, and the old ones are removed.",
            inputSchema: .object([
                "type": "object",
                "properties": [
                    "project": project,
                    "file": file,
                    "new_name": ["type": "string", "description": "The new name, with or without the .model extension."]
                ],
                "required": ["project", "file", "new_name"]
            ])
        ),

        Tool(
            name: "delete_model_file",
            description: "Delete a model file from the project. The code generated from it is removed on the next generate. This is irreversible.",
            inputSchema: .object([
                "type": "object",
                "properties": ["project": project, "file": file],
                "required": ["project", "file"]
            ])
        ),

        Tool(
            name: "get_diagnostics",
            description: "Compile the project and return its problems, with source excerpts and carets. Pass a file to narrow the report to that file; the whole project is still compiled, because the cause is often elsewhere.",
            inputSchema: .object([
                "type": "object",
                "properties": [
                    "project": project,
                    "file": ["type": "string", "description": "Optional. Narrow the report to this file."]
                ],
                "required": ["project"]
            ])
        ),

        Tool(
            name: "get_generated_code",
            description: "Return the Swift and/or Kotlin generated from the project, without writing anything to disk. Name a file to see just what it produces; omit it to get everything including the shared ModelForgeSupport file.",
            inputSchema: .object([
                "type": "object",
                "properties": [
                    "project": project,
                    "file": ["type": "string", "description": "Optional. Only the code generated from this model file."],
                    "language": ["type": "string", "enum": ["swift", "kotlin", "both"], "default": "both"]
                ],
                "required": ["project"]
            ])
        ),

        Tool(
            name: "generate",
            description: "Write the generated Swift and Kotlin to the project's configured output folders. Refuses while the project has errors, or before a Kotlin package and an output folder are set. Files whose contents have not changed are left untouched, and files a previous run wrote that this one does not produce are deleted.",
            inputSchema: .object([
                "type": "object",
                "properties": ["project": project],
                "required": ["project"]
            ])
        ),

        Tool(
            name: "get_configuration",
            description: "Read a project's emitter settings: Kotlin package, output folders, Swift module and access level, and which protocols the generated Swift conforms to.",
            inputSchema: .object([
                "type": "object",
                "properties": ["project": project],
                "required": ["project"]
            ])
        ),

        Tool(
            name: "set_configuration",
            description: "Change a project's emitter settings. Only the fields you pass are changed. Output paths are stored relative to the .modelforge bundle, so give them relative to it.",
            inputSchema: .object([
                "type": "object",
                "properties": [
                    "project": project,
                    "kotlin_package": ["type": "string", "description": "Package every generated Kotlin file declares, e.g. com.example.app.models."],
                    "kotlin_output": ["type": "string", "description": "Folder for .kt files, relative to the bundle, e.g. ../android/app/src/main/generated/models."],
                    "swift_module": ["type": "string", "description": "Module name, recorded in the generated header."],
                    "swift_output": ["type": "string", "description": "Folder for .swift files, relative to the bundle, e.g. ../ios/Generated/Models."],
                    "swift_access_level": ["type": "string", "enum": ["internal", "public"]]
                ],
                "required": ["project"]
            ])
        )
    ]
}
