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
    @Bindable var settings: AppSettings
    let theme: EditorTheme

    private var fontSize: Double { settings.editorFontSize }

    /// The picker's selection: reading it combines the window's language with the app's
    /// layout, and setting it writes both back.
    private var choice: Binding<PreviewChoice> {
        Binding(
            get: { PreviewChoice(layout: settings.previewLayout,
                                 language: session.previewLanguage) },
            set: { new in
                settings.previewLayout = new.layout
                if let language = new.language { session.previewLanguage = language }
            })
    }

    var body: some View {
        switch settings.previewLayout {
        case .single:
            pane(for: session.previewLanguage, showsPicker: true)
        case .both:
            VSplitView {
                // The picker stays at the top of the column in both layouts, rather than
                // moving to a different pane depending on which one you are in.
                pane(for: .swift, showsPicker: true)
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
                Picker("", selection: choice) {
                    ForEach(PreviewChoice.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .help("Which generated code to show")
            }

            // No language label next to the picker: the file name below it already ends
            // in .swift or .kt, and in a column this narrow the two together squeeze the
            // name down to nothing.
            if !showsPicker {
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
