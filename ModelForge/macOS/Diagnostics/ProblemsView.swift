//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI
import ModelForgeKit

/// A one-line summary of the project's health, which expands into the problems list.
struct StatusStrip: View {

    @Bindable var session: ProjectSession

    var body: some View {
        Button {
            guard !session.diagnostics.isEmpty else { return }
            session.isProblemsListExpanded.toggle()
        } label: {
            HStack(spacing: 6) {
                icon
                Text(session.statusSummary)
                    .font(.callout)
                Spacer()
                if !session.diagnostics.isEmpty {
                    Image(systemName: session.isProblemsListExpanded ? "chevron.down" : "chevron.up")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(.bar)
        .help(session.diagnostics.isEmpty ? "" : "Show problems")
    }

    @ViewBuilder private var icon: some View {
        if session.diagnostics.isEmpty {
            Image(systemName: "checkmark.circle")
                .foregroundStyle(.secondary)
        } else if session.hasErrors {
            Image(systemName: "exclamationmark.octagon.fill")
                .foregroundStyle(.red)
        } else {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }
}

/// Every problem in the project, the selected file's first.
///
/// Whole-project rather than just the open file: with one flat namespace, a mistake in
/// another file is usually the actual cause of what you are seeing here.
struct ProblemsView: View {

    let session: ProjectSession

    var body: some View {
        ScrollViewReader { _ in
            List {
                ForEach(session.orderedDiagnostics) { diagnostic in
                    DiagnosticRow(diagnostic: diagnostic,
                                  fileName: session.fileName(for: diagnostic.range.file),
                                  showsFileName: showsFileName(for: diagnostic))
                        .contentShape(Rectangle())
                        .onTapGesture { session.reveal(diagnostic) }
                        .contextMenu {
                            Button("Copy") { copy(diagnostic) }
                        }
                }
            }
            .listStyle(.inset)
        }
    }

    private func showsFileName(for diagnostic: Diagnostic) -> Bool {
        guard case .file(let selected) = session.selection else { return true }
        return diagnostic.range.file != selected
    }

    private func copy(_ diagnostic: Diagnostic) {
        guard let result = session.result else { return }
        let text = DiagnosticRenderer.render(diagnostic, in: result.filesByID)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

struct DiagnosticRow: View {

    let diagnostic: Diagnostic
    let fileName: String
    let showsFileName: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbolName)
                .foregroundStyle(diagnostic.severity == .error ? Color.red : Color.orange)
                .font(.callout)

            VStack(alignment: .leading, spacing: 2) {
                Text(diagnostic.message)
                    .font(.callout)
                    .textSelection(.enabled)

                ForEach(Array(diagnostic.notes.enumerated()), id: \.offset) { _, note in
                    Text("help: \(note.message)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            Text(location)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }

    private var symbolName: String {
        switch diagnostic.severity {
        case .error: "exclamationmark.octagon.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .note: "info.circle"
        }
    }

    private var location: String {
        let position = "\(diagnostic.range.start.line):\(diagnostic.range.start.column)"
        return showsFileName ? "\(fileName):\(position)" : position
    }
}
