//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI
import ModelForgeKit

/// The project's contents: settings, then every `.model` file.
struct FileListView: View {

    @Bindable var session: ProjectSession

    @State private var renaming: ProjectSource?
    @State private var renameText = ""
    @State private var renameError: String?
    @State private var deleting: ProjectSource?

    var body: some View {
        List(selection: $session.selection) {
            Section {
                settingsRow
            }

            Section("Models") {
                ForEach(session.sources) { file in
                    fileRow(file)
                        .tag(ProjectSession.Selection.file(file.id))
                        .contextMenu {
                            Button("Rename…") { beginRenaming(file) }
                            Button("Delete…", role: .destructive) { deleting = file }
                        }
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 190, idealWidth: 210, maxWidth: 320)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            addButton
        }
        .sheet(item: $renaming) { file in
            RenameSheet(file: file,
                        text: $renameText,
                        error: $renameError,
                        onCommit: { commitRename(file) },
                        onCancel: { renaming = nil })
        }
        .alert("Delete “\(deleting?.name ?? "")”?", isPresented: deletingBinding) {
            Button("Cancel", role: .cancel) { deleting = nil }
            Button("Delete", role: .destructive) {
                if let file = deleting { session.delete(file.id) }
                deleting = nil
            }
        } message: {
            Text("The code generated from this file will be removed the next time you generate.")
        }
    }

    // MARK: Rows

    private var settingsRow: some View {
        Label {
            HStack {
                Text("Project Settings")
                Spacer()
                // Until the Kotlin package is set, generated Kotlin would land in
                // somebody else's namespace — so say so before it happens.
                if !session.configuration.kotlin.isPackageConfigured {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.orange)
                        .help("Set a Kotlin package before generating")
                }
            }
        } icon: {
            Image(systemName: "gearshape")
        }
        .tag(ProjectSession.Selection.settings)
    }

    private func fileRow(_ file: ProjectSource) -> some View {
        Label {
            HStack(spacing: 4) {
                Text(file.displayName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                if let severity = session.worstSeverity(for: file.id) {
                    Image(systemName: severity == .error
                          ? "exclamationmark.octagon.fill"
                          : "exclamationmark.triangle.fill")
                        .foregroundStyle(severity == .error ? .red : .orange)
                        .help(problemSummary(for: file))
                }
            }
        } icon: {
            Image(systemName: "doc.text")
        }
    }

    private func problemSummary(for file: ProjectSource) -> String {
        let problems = session.diagnostics(for: file.id)
        let errors = problems.count { $0.severity == .error }
        let warnings = problems.count { $0.severity == .warning }
        var parts: [String] = []
        if errors > 0 { parts.append("\(errors) \(errors == 1 ? "error" : "errors")") }
        if warnings > 0 { parts.append("\(warnings) \(warnings == 1 ? "warning" : "warnings")") }
        return parts.joined(separator: ", ")
    }

    private var addButton: some View {
        VStack(spacing: 0) {
            Divider()
            Button {
                session.addFile()
            } label: {
                Label("New Model File", systemImage: "plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(.bar)
    }

    // MARK: Renaming

    private var deletingBinding: Binding<Bool> {
        Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })
    }

    private func beginRenaming(_ file: ProjectSource) {
        renameText = file.displayName
        renameError = nil
        renaming = file
    }

    private func commitRename(_ file: ProjectSource) {
        if let error = session.rename(file.id, to: renameText) {
            renameError = error
        } else {
            renaming = nil
        }
    }
}

/// Renaming a file also renames what it generates, which is why the sheet says so.
private struct RenameSheet: View {

    let file: ProjectSource
    @Binding var text: String
    @Binding var error: String?
    let onCommit: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rename Model File")
                .font(.headline)

            TextField("Name", text: $text)
                .textFieldStyle(.roundedBorder)
                .onSubmit(onCommit)

            if let error {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
            } else {
                Text("The generated files will be renamed to match the next time you generate.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Rename", action: onCommit)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}
