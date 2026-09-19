//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation
import MCP

/// Builds an MCP ``Server`` wired to an ``MCPModelService``. One server instance is created per
/// HTTP session by ``MCPServerController``.
nonisolated enum ModelForgeMCPServerFactory {

    /// A compact reference for the DSL, handed to the client model as instructions.
    ///
    /// This matters more here than in most MCP servers: the agent is being asked to *write* a
    /// language it has never seen. Without this it would guess at Swift or Protobuf syntax and
    /// spend several tool calls discovering the differences.
    private static let instructions = """
    ModelForge defines data models once in a small DSL and generates matching Swift and Kotlin, \
    so an iOS app and an Android app share one model layer.

    Addressing: reference a project by the name in its window title or by the path to its \
    .modelforge bundle; reference a model file by name, with or without the .model extension. \
    Call list_projects first.

    Editing: write_model_file replaces a file's entire contents, so read it first unless you are \
    creating it. Use check_model_source to validate syntax without saving. Changes appear in the \
    open window immediately; generate writes the Swift and Kotlin to disk.

    THE LANGUAGE

    Every .model file in a project shares one flat namespace — types refer to each other with no \
    import, and there is no import statement.

        /// Doc comments become documentation in both languages.
        model User {
            @json("user_id")          // renames the field on the wire
            id: UUID
            name: String
            email: String?            // nullable; the key is still required
            status: UserStatus = .active
            createdAt: Instant
            @transient                // kept out of serialization; needs a default
            isSelected: Bool = false
        }

        enum UserStatus { active  suspended  deleted }

        @extensible                   // accepts values this build has not heard of,
        enum Plan { free  pro }       // keeping the raw string; use it for server-owned enums

        @discriminator("kind")        // defaults to "type"
        union PaymentMethod {
            card(Card)                // a union case's payload must be a model
            applePay(ApplePay)
        }

        typealias UserID = UUID

        @identifiable                 // Swift Identifiable, using the id field
        model Account { id: UUID }
        @identifiable("code")         // or name another field; a bridging id is generated
        model Country { code: String }

    Scalars: String, Bool, Int32, Int64, Float, Double, Decimal, UUID, URL, Date, Instant, Duration.
    Containers: T?, [T], Set<T>, Map<K, V>, and any nesting of those.

    Two rules that surprise people:

    - There is NO Int. Its width differs between Swift and Kotlin, so a server-issued identifier \
      could decode on iOS and overflow on Android. Write Int32 or Int64.
    - A default means the key MAY BE ABSENT from the payload. `archived: Bool = false` decodes \
      from JSON that omits "archived", on both platforms. A field without a default always \
      requires its key, even when its type is nullable.

    Also: a model may not contain itself except through a list, set, map or union; two fields may \
    not serialize to the same name; and a union payload may not have a field named the same as the \
    discriminator.

    Diagnostics are precise and usually tell you the fix — read the "help" lines before guessing.
    """

    static func makeServer(service: MCPModelService) async -> Server {
        let server = Server(
            name: "ModelForge",
            version: "1.0.0",
            instructions: instructions,
            capabilities: .init(tools: .init(listChanged: false))
        )

        await server.withMethodHandler(ListTools.self) { _ in
            .init(tools: MCPToolCatalog.tools)
        }

        await server.withMethodHandler(CallTool.self) { params in
            do {
                let text = try await dispatch(params, service: service)
                return .init(content: [.text(text: text, annotations: nil, _meta: nil)], isError: false)
            } catch let error as MCPToolError {
                return .init(content: [.text(text: error.message, annotations: nil, _meta: nil)], isError: true)
            } catch {
                return .init(content: [.text(text: "Internal error: \(error)", annotations: nil, _meta: nil)], isError: true)
            }
        }

        return server
    }

    // MARK: - Dispatch

    private static func dispatch(_ params: CallTool.Parameters,
                                 service: MCPModelService) async throws -> String {
        let args = params.arguments ?? [:]

        func requireString(_ key: String) throws -> String {
            guard let value = args[key]?.stringValue, !value.isEmpty else {
                throw MCPToolError.invalidArgument("Missing required argument \"\(key)\".")
            }
            return value
        }
        func optionalString(_ key: String) -> String? {
            guard let value = args[key]?.stringValue else { return nil }
            return value
        }

        switch params.name {
        case "list_projects":
            return MCPJSON.string(await service.listProjects())

        case "open_project":
            return MCPJSON.string(try await service.openProject(path: try requireString("path")))

        case "list_model_files":
            return MCPJSON.string(try await service.listModelFiles(project: try requireString("project")))

        case "read_model_file":
            return try await service.readModelFile(project: try requireString("project"),
                                                   file: try requireString("file"))

        case "check_model_source":
            return MCPJSON.string(try await service.checkSource(project: try requireString("project"),
                                                                file: try requireString("file"),
                                                                source: try requireString("source")))

        case "write_model_file":
            return MCPJSON.string(try await service.writeModelFile(project: try requireString("project"),
                                                                   file: try requireString("file"),
                                                                   source: try requireString("source")))

        case "rename_model_file":
            return MCPJSON.string(try await service.renameModelFile(project: try requireString("project"),
                                                                    file: try requireString("file"),
                                                                    to: try requireString("new_name")))

        case "delete_model_file":
            return try await service.deleteModelFile(project: try requireString("project"),
                                                     file: try requireString("file"))

        case "get_diagnostics":
            return MCPJSON.string(try await service.diagnostics(project: try requireString("project"),
                                                                file: optionalString("file")))

        case "get_generated_code":
            return MCPJSON.string(try await service.generatedCode(project: try requireString("project"),
                                                                  file: optionalString("file"),
                                                                  language: optionalString("language")))

        case "generate":
            return MCPJSON.string(try await service.generate(project: try requireString("project")))

        case "get_configuration":
            return MCPJSON.string(try await service.configuration(project: try requireString("project")))

        case "set_configuration":
            return MCPJSON.string(try await service.setConfiguration(
                project: try requireString("project"),
                kotlinPackage: optionalString("kotlin_package"),
                kotlinOutput: optionalString("kotlin_output"),
                swiftModule: optionalString("swift_module"),
                swiftOutput: optionalString("swift_output"),
                swiftAccessLevel: optionalString("swift_access_level")))

        default:
            throw MCPToolError.invalidArgument("Unknown tool \"\(params.name)\".")
        }
    }
}
