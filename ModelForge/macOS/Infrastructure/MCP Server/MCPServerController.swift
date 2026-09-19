//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation
import MCP
import OSLog
@preconcurrency import NIOCore
@preconcurrency import NIOPosix
@preconcurrency import NIOHTTP1

/// A localhost-only NIO HTTP server that speaks the MCP streamable-HTTP protocol, adapted from the
/// `mcp-swift-sdk` package's reference conformance server (`MCPConformance/Server/HTTPApp.swift`).
///
/// The MCP SDK's ``StatefulHTTPServerTransport`` implements the protocol (sessions, SSE) but does
/// not open a socket — this type supplies the NIO listener and routes requests to one `Server` +
/// transport per MCP session (keyed by `Mcp-Session-Id`).
actor MCPServerController {

    nonisolated struct Configuration: Sendable {
        var host: String
        var port: Int
        var endpoint: String
        var sessionTimeout: TimeInterval
        var retryInterval: Int?

        init(
            host: String = "127.0.0.1",
            port: Int,
            endpoint: String = "/mcp",
            sessionTimeout: TimeInterval = 3600,
            retryInterval: Int? = 1000
        ) {
            self.host = host
            self.port = port
            self.endpoint = endpoint
            self.sessionTimeout = sessionTimeout
            self.retryInterval = retryInterval
        }
    }

    /// Factory function creating one MCP `Server` per session.
    typealias ServerFactory = @Sendable (String, StatefulHTTPServerTransport) async throws -> Server

    private struct SessionContext {
        let server: Server
        let transport: StatefulHTTPServerTransport
        var lastAccessedAt: Date
    }

    private struct FixedSessionIDGenerator: SessionIDGenerator {
        let sessionID: String
        func generateSessionID() -> String { sessionID }
    }

    /// Probes a JSON-RPC request body for its method name, without depending on the SDK's
    /// package-scoped `JSONRPCMessageKind`.
    private nonisolated struct RPCMethodProbe: Decodable {
        let method: String?
    }

    private let configuration: Configuration
    private let serverFactory: ServerFactory
    private let validationPipeline: (any HTTPRequestValidationPipeline)?
    private var sessions: [String: SessionContext] = [:]
    private var channel: Channel?
    private var group: MultiThreadedEventLoopGroup?
    private var cleanupTask: Task<Void, Never>?

    nonisolated static let log = Logger(subsystem: "pizza.martin.ModelForge", category: "MCPServer")

    init(
        configuration: Configuration,
        validationPipeline: (any HTTPRequestValidationPipeline)? = nil,
        serverFactory: @escaping ServerFactory
    ) {
        self.configuration = configuration
        self.validationPipeline = validationPipeline
        self.serverFactory = serverFactory
    }

    var endpoint: String { configuration.endpoint }

    // MARK: - Lifecycle

    /// Starts listening. Returns once bound; does not block for the server's lifetime.
    func start() async throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { [weak self] channel in
                guard let self else {
                    return channel.eventLoop.makeFailedFuture(CancellationError())
                }
                return channel.pipeline.configureHTTPServerPipeline().flatMap {
                    channel.pipeline.addHandler(MCPNIOHTTPHandler(controller: self))
                }
            }
            .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 1)

        do {
            let channel = try await bootstrap.bind(host: configuration.host, port: configuration.port).get()
            self.group = group
            self.channel = channel
            cleanupTask = Task { [weak self] in await self?.sessionCleanupLoop() }
            Self.log.info("MCP server listening on \(self.configuration.host, privacy: .public):\(self.configuration.port)")
        } catch {
            try? await group.shutdownGracefully()
            throw error
        }
    }

    /// Stops listening, closes every session, and releases the event loop group.
    func stop() async {
        cleanupTask?.cancel()
        cleanupTask = nil
        await closeAllSessions()
        try? await channel?.close()
        channel = nil
        try? await group?.shutdownGracefully()
        group = nil
        Self.log.info("MCP server stopped")
    }

    // MARK: - Request routing

    func handleHTTPRequest(_ request: HTTPRequest) async -> HTTPResponse {
        let sessionID = request.header(HTTPHeaderName.sessionID)

        if let sessionID, var session = sessions[sessionID] {
            session.lastAccessedAt = Date()
            sessions[sessionID] = session

            let response = await session.transport.handleRequest(request)
            if request.method.uppercased() == "DELETE", response.statusCode == 200 {
                sessions.removeValue(forKey: sessionID)
            }
            return response
        }

        if request.method.uppercased() == "POST",
           let body = request.body,
           let probe = try? JSONDecoder().decode(RPCMethodProbe.self, from: body),
           probe.method == "initialize" {
            return await createSessionAndHandle(request)
        }

        if sessionID != nil {
            return .error(statusCode: 404, .invalidRequest("Not Found: Session not found or expired"))
        }
        return .error(statusCode: 400, .invalidRequest("Bad Request: Missing \(HTTPHeaderName.sessionID) header"))
    }

    // MARK: - Session management

    private func createSessionAndHandle(_ request: HTTPRequest) async -> HTTPResponse {
        let sessionID = UUID().uuidString
        let transport = StatefulHTTPServerTransport(
            sessionIDGenerator: FixedSessionIDGenerator(sessionID: sessionID),
            validationPipeline: validationPipeline,
            retryInterval: configuration.retryInterval,
            logger: nil
        )

        do {
            let server = try await serverFactory(sessionID, transport)
            try await server.start(transport: transport)
            sessions[sessionID] = SessionContext(server: server, transport: transport, lastAccessedAt: Date())

            let response = await transport.handleRequest(request)
            if case .error = response {
                sessions.removeValue(forKey: sessionID)
                await transport.disconnect()
            }
            return response
        } catch {
            await transport.disconnect()
            return .error(statusCode: 500, .internalError("Failed to create session: \(error.localizedDescription)"))
        }
    }

    private func closeSession(_ sessionID: String) async {
        guard let session = sessions.removeValue(forKey: sessionID) else { return }
        await session.server.stop()
        await session.transport.disconnect()
    }

    private func closeAllSessions() async {
        for sessionID in sessions.keys {
            await closeSession(sessionID)
        }
    }

    private func sessionCleanupLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(60))
            if Task.isCancelled { return }

            let now = Date()
            let expired = sessions.filter { now.timeIntervalSince($0.value.lastAccessedAt) > configuration.sessionTimeout }
            for sessionID in expired.keys {
                await closeSession(sessionID)
            }
        }
    }
}
