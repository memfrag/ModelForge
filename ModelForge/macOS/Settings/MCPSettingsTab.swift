//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI

/// Turns the embedded MCP server on and off, and shows how to connect to it.
struct MCPSettingsTab: View {

    @Environment(AppSettings.self) private var settings
    @Environment(MCPServerManager.self) private var manager

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                Toggle("Allow agents to connect", isOn: $settings.mcpServerEnabled)

                LabeledContent("Port") {
                    TextField("Port", value: $settings.mcpServerPort, format: .number.grouping(.never))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)
                        .disabled(!settings.mcpServerEnabled)
                }

                LabeledContent("Status") {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 8, height: 8)
                        Text(statusText)
                            .font(.callout)
                            .foregroundStyle(manager.status.isRunning ? .primary : .secondary)
                    }
                }
            } header: {
                Text("Model Context Protocol")
            } footer: {
                Text("ModelForge can expose the projects you have open to a coding agent, which can then read your models, edit them, and generate Swift and Kotlin. The server listens on 127.0.0.1 only and is never reachable from another machine.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let command = manager.claudeCommand {
                Section {
                    Text(command)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 6))

                    Button("Copy Command") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(command, forType: .string)
                    }
                } header: {
                    Text("Connecting Claude Code")
                } footer: {
                    Text("Run this once in a terminal. The agent sees whichever projects are open in ModelForge, and anything it changes appears in the window straight away.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var statusColor: Color {
        switch manager.status {
        case .running: .green
        case .starting: .orange
        case .failed: .red
        case .stopped: .secondary
        }
    }

    private var statusText: String {
        switch manager.status {
        case .stopped: "Not running"
        case .starting: "Starting…"
        case .running(let port): "Listening on 127.0.0.1:\(port)"
        case .failed(let message): message
        }
    }
}
