//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation
import OSLog

/// Owns the embedded MCP server's lifecycle, reacting to ``AppSettings/mcpServerEnabled`` and
/// ``AppSettings/mcpServerPort`` so the Settings UI never has to start or stop it explicitly.
@Observable @MainActor final class MCPServerManager {

    enum Status: Equatable {
        case stopped
        case starting
        case running(port: Int)
        case failed(String)

        var isRunning: Bool {
            if case .running = self { return true }
            return false
        }
    }

    private(set) var status: Status = .stopped

    /// The endpoint an MCP client connects to, while running.
    var url: URL? {
        guard case .running(let port) = status else { return nil }
        return URL(string: "http://127.0.0.1:\(port)/mcp")
    }

    /// The command that registers this server with Claude Code.
    var claudeCommand: String? {
        guard let url else { return nil }
        return "claude mcp add --transport http modelforge \(url.absoluteString)"
    }

    @ObservationIgnored private let appSettings: AppSettings
    @ObservationIgnored private let service: MCPModelService
    @ObservationIgnored private var controller: MCPServerController?
    /// Bumped on every sync, so a stale start that finishes late is discarded.
    @ObservationIgnored private var generation = 0

    private static let log = Logger(subsystem: "pizza.martin.ModelForge", category: "MCPServerManager")

    init(appSettings: AppSettings, service: MCPModelService) {
        self.appSettings = appSettings
        self.service = service
    }

    /// Starts observing settings and performs the initial sync. Call once at launch.
    func applyAtLaunch() {
        observeSettings()
        Task { await syncWithSettings() }
    }

    private func observeSettings() {
        withObservationTracking {
            _ = appSettings.mcpServerEnabled
            _ = appSettings.mcpServerPort
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.syncWithSettings()
                // Observation fires once, so re-arm it.
                self.observeSettings()
            }
        }
    }

    private func syncWithSettings() async {
        generation += 1
        let myGeneration = generation

        if let controller {
            self.controller = nil
            await controller.stop()
        }
        guard myGeneration == generation else { return }

        guard appSettings.mcpServerEnabled else {
            status = .stopped
            return
        }

        let port = appSettings.mcpServerPort
        guard (1024...65535).contains(port) else {
            status = .failed("Port must be between 1024 and 65535.")
            return
        }

        status = .starting
        let service = self.service
        let newController = MCPServerController(
            configuration: .init(port: port),
            serverFactory: { _, _ in await ModelForgeMCPServerFactory.makeServer(service: service) }
        )

        do {
            try await newController.start()
            guard myGeneration == generation else {
                await newController.stop()
                return
            }
            controller = newController
            status = .running(port: port)
        } catch {
            guard myGeneration == generation else { return }
            Self.log.error("Failed to start MCP server on port \(port): \(error.localizedDescription)")
            status = .failed("Port \(port) is already in use, or could not be bound.")
        }
    }
}
