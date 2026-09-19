//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI
import ModelForgeKit

/// The generated code for the selected file.
///
/// Output is one file per source file, so this pane always shows exactly what the file in
/// the editor produces — the two columns stay in step with no mapping to explain.
struct CodePreviewPane: View {

    @Bindable var session: ProjectSession
    let theme: EditorTheme
    let fontSize: Double
    let layout: PreviewLayout

    var body: some View {
        switch layout {
        case .single:
            pane(for: session.previewLanguage, showsPicker: true)
        case .both:
            VSplitView {
                pane(for: .swift, showsPicker: false)
                pane(for: .kotlin, showsPicker: false)
            }
        }
    }

    private func pane(for language: Language, showsPicker: Bool) -> some View {
        VStack(spacing: 0) {
            header(for: language, showsPicker: showsPicker)
            Divider()
            content(for: language)
        }
        .frame(minHeight: 120)
    }

    private func header(for language: Language, showsPicker: Bool) -> some View {
        HStack(spacing: 8) {
            if showsPicker {
                Picker("", selection: $session.previewLanguage) {
                    ForEach(Language.allCases, id: \.self) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            } else {
                Text(language.displayName)
                    .font(.callout.weight(.medium))
            }

            if let file = session.previewFile(for: language) {
                Text(file.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Button {
                copy(language)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help("Copy \(language.displayName)")
            .disabled(session.previewFile(for: language) == nil)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.bar)
    }

    @ViewBuilder private func content(for language: Language) -> some View {
        if let file = session.previewFile(for: language) {
            GeneratedCodeView(text: file.contents,
                              language: language,
                              knownTypeNames: session.knownTypeNames,
                              theme: theme,
                              fontSize: fontSize)
        } else {
            ContentUnavailableView {
                Label("Nothing to show", systemImage: "curlybraces")
            } description: {
                Text(session.result == nil
                     ? "Compiling…"
                     : "Select a model file to see the \(language.displayName) it generates.")
            }
        }
    }

    private func copy(_ language: Language) {
        guard let file = session.previewFile(for: language) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(file.contents, forType: .string)
    }
}
