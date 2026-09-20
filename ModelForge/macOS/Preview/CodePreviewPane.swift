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

    var body: some View {
        // The wrapper is not decoration. Without it the `VSplitView` is the horizontal
        // split's own subview, and a nested split view's width constraints beat the frame
        // hints put on this column — so choosing Both used to shrink the previews from
        // 539pt to 321pt and leave them there. Inside a plain container it is just content.
        VStack(spacing: 0) {
            switch settings.previewLayout {
            case .single:
                pane(for: session.previewLanguage)
            case .both:
                VSplitView {
                    pane(for: .swift)
                    pane(for: .kotlin)
                }
            }
        }
    }

    private func pane(for language: Language) -> some View {
        VStack(spacing: 0) {
            header(for: language)
            Divider()
            content(for: language)
        }
        .frame(minHeight: 120)
    }

    /// Every pane says which language it is, the same way: the mark, the name, the file.
    ///
    /// The control that chooses between them is in the window toolbar rather than in here,
    /// so neither pane is the one that happens to carry it.
    private func header(for language: Language) -> some View {
        HStack(spacing: 8) {
            LanguageLabel(language: language)
                .font(.callout.weight(.medium))

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

    /// The longest of the files on screen, so both gutters are the same width when both
    /// languages are shown. Zero when only one is, where there is nothing to line up with.
    private var alignedLineCount: Int {
        guard settings.previewLayout == .both else { return 0 }
        return Language.allCases
            .compactMap { session.previewFile(for: $0)?.contents.count(where: { $0 == "\n" }) }
            .max() ?? 0
    }

    @ViewBuilder private func content(for language: Language) -> some View {
        if let file = session.previewFile(for: language) {
            GeneratedCodeView(text: file.contents,
                              language: language,
                              knownTypeNames: session.knownTypeNames,
                              theme: theme,
                              fontSize: fontSize,
                              alignedWith: alignedLineCount)
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
