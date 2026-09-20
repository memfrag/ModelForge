//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI
import SwiftUIToolbox
import ModelForgeKit

/// One project window: files on the left, the editor in the middle, the generated code on
/// the right.
struct ProjectWindow: View {

    @Environment(AppSettings.self) private var settings
    @Environment(EditorTheme.self) private var theme
    @Environment(OpenProjectRegistry.self) private var openProjects

    @State private var session: ProjectSession
    @State private var watcher: ProjectWatcher?

    private let document: ProjectDocument

    init(document: ProjectDocument, settings: AppSettings) {
        self.document = document
        _session = State(initialValue: ProjectSession(document: document, settings: settings))
    }

    var body: some View {
        // Banners sit above the split view rather than inside a safe-area inset, which
        // would overlay the preview pane's own header instead of moving it down.
        VStack(spacing: 0) {
            banners
            splitView
        }
    }

    private var splitView: some View {
        NavigationSplitView {
            FileListView(session: session)
        } detail: {
            detail
        }
        .navigationTitle(document.fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled")
        .navigationSubtitle(session.statusSummary)
        .focusedSceneValue(\.projectSession, session)
        .toolbar { toolbar }
        .onChange(of: document.fileURL) { _, _ in startWatching() }
        // Compilation follows the document rather than each individual edit, so content
        // loaded from disk refreshes the previews just like typing does.
        .onChange(of: document.sources) { _, _ in session.sourcesChanged() }
        .onChange(of: document.configuration) { _, _ in session.configurationChanged() }
        .task { session.compileNow() }
        .onAppear {
            startWatching()
            // Registering makes this project visible to the embedded MCP server.
            openProjects.register(session)
        }
        .onDisappear {
            watcher = nil
            openProjects.deregister(session)
        }
        .background(AlwaysOnTop())
    }

    // MARK: Detail

    @ViewBuilder private var detail: some View {
        switch session.selection {
        case .settings:
            ProjectSettingsForm(session: session)
                .background(PaneBackground())

        case .graph:
            TypeGraphView(session: session, theme: theme)

        case .file:
            if let source = session.selectedSource {
                HSplitView {
                    editorColumn(for: source)
                    CodePreviewPane(session: session,
                                    settings: settings,
                                    theme: theme)
                        .frame(minWidth: 320, idealWidth: 460, maxWidth: .infinity)
                }
            } else {
                ContentUnavailableView("No file selected", systemImage: "doc.text")
            }
        }
    }

    private func editorColumn(for source: ProjectSource) -> some View {
        VStack(spacing: 0) {
            SourceEditorView(source: source,
                             session: session,
                             diagnostics: session.diagnostics(for: source.id),
                             diagnosedText: session.diagnosedText(for: source.id),
                             theme: theme,
                             fontSize: settings.editorFontSize)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            StatusStrip(session: session)

            if session.isProblemsListExpanded, !session.diagnostics.isEmpty {
                Divider()
                ProblemsView(session: session)
                    .frame(height: 150)
            }
        }
        .frame(minWidth: 320, idealWidth: 520, maxWidth: .infinity)
        .background(PaneBackground())
    }

    // MARK: Chrome

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Picker("Preview", selection: PreviewChoice.binding(session: session,
                                                               settings: settings)) {
                ForEach(PreviewChoice.allCases) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .help("Which generated code to show")
            // Meaningless while the settings form or the graph is up: there is no preview
            // column on screen to apply it to.
            .disabled(session.selectedFileID == nil)
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                session.generate()
            } label: {
                Label("Generate", systemImage: "hammer")
            }
            .help(session.generationBlocker ?? "Generate Swift and Kotlin")
            .disabled(!session.canGenerate)
        }
    }

    @ViewBuilder private var banners: some View {
        VStack(spacing: 0) {
            if let change = session.externalChange {
                ExternalChangeBanner(session: session, change: change)
                Divider()
            }
            if let report = session.generationReport {
                GenerationBanner(session: session, report: report)
                Divider()
            }
        }
    }

    // MARK: Watching

    /// Watch the bundle so a `git checkout` underneath an open window is noticed.
    private func startWatching() {
        guard let url = document.fileURL else {
            watcher = nil
            return
        }
        watcher = ProjectWatcher(url: url) { [weak session] in
            session?.projectChangedOnDisk()
        }
    }
}

/// Shown after Generate.
private struct GenerationBanner: View {

    let session: ProjectSession
    let report: GenerationReport

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: report.failure == nil ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(report.failure == nil ? Color.green : Color.orange)
            Text(report.summary)
                .font(.callout)
            Spacer()
            if report.failure == nil, !report.destinations.isEmpty {
                Button("Reveal in Finder") { session.revealOutput() }
                    .buttonStyle(.link)
            }
            Button {
                session.generationReport = nil
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

/// Shown when the project changed on disk while there were unsaved edits.
private struct ExternalChangeBanner: View {

    let session: ProjectSession
    let change: ExternalChange

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundStyle(.orange)
            Text("This project changed on disk.")
                .font(.callout)
            Spacer()
            Button("Keep Mine") { session.externalChange = nil }
                .buttonStyle(.link)
            Button("Reload") { session.acceptExternalChange() }
                .buttonStyle(.link)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
