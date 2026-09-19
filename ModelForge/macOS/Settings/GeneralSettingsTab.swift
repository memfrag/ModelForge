//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI
import SettingsUI

struct GeneralSettingsTab: View {

    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                Picker("Appearance", selection: $settings.colorScheme) {
                    ForEach(AppColorScheme.allCases, id: \.self) { scheme in
                        Label(scheme.description, systemImage: scheme.icon).tag(scheme)
                    }
                }
            }

            Section {
                Picker("Preview column", selection: $settings.previewLayout) {
                    ForEach(PreviewLayout.allCases) { layout in
                        Text(layout.description).tag(layout)
                    }
                }

                LabeledContent("Update previews after") {
                    VStack(alignment: .leading, spacing: 2) {
                        Slider(value: debounceBinding, in: 100...1000, step: 50)
                        Text("\(settings.previewDebounceMilliseconds) ms")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Previews")
            } footer: {
                Text("How long to wait after you stop typing before regenerating. Compiling itself takes about a millisecond, so this is about how twitchy the panes feel.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var debounceBinding: Binding<Double> {
        Binding(get: { Double(settings.previewDebounceMilliseconds) },
                set: { settings.previewDebounceMilliseconds = Int($0) })
    }
}
