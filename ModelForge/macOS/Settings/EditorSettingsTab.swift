//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI
import ModelForgeKit

/// Font size and syntax colours.
///
/// One set of colours covers the DSL editor and both generated-code previews, because the
/// highlighter classifies all three into the same handful of kinds.
struct EditorSettingsTab: View {

    @Environment(AppSettings.self) private var settings
    @Environment(EditorTheme.self) private var theme

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                LabeledContent("Font size") {
                    VStack(alignment: .leading, spacing: 2) {
                        Slider(value: $settings.editorFontSize, in: 9...20, step: 1)
                        Text("\(Int(settings.editorFontSize)) pt")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                ForEach(HighlightKind.allCases, id: \.self) { kind in
                    LabeledContent(kind.displayName) {
                        HStack(spacing: 8) {
                            ColorPicker("", selection: theme.binding(for: kind), supportsOpacity: false)
                                .labelsHidden()
                            if theme.isCustomized(kind) {
                                Button("Reset") { theme.reset(kind) }
                                    .buttonStyle(.link)
                            }
                        }
                    }
                }
            } header: {
                Text("Syntax colours")
            } footer: {
                HStack {
                    Text("Used by the model editor and by both generated-code panes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Reset All") { theme.resetToDefaults() }
                        .disabled(!theme.hasCustomColors)
                }
            }
        }
        .formStyle(.grouped)
    }
}
