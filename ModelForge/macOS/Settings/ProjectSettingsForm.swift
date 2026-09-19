//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI
import ModelForgeKit

/// The project's `Config.json`, edited as a form.
///
/// Configuration is deliberately not part of the DSL: the language describes data shape,
/// and emitter policy belongs outside the schema. It is JSON on disk rather than DSL
/// syntax so there is one parser, and a form rather than a text editor so the type
/// mappings can be a real table instead of hand-typed strings.
struct ProjectSettingsForm: View {

    let session: ProjectSession

    var body: some View {
        Form {
            Section {
                TextField("Package", text: kotlinPackage, prompt: Text("com.example.models"))
                    .textFieldStyle(.roundedBorder)
                if !session.configuration.kotlin.isPackageConfigured {
                    Label("Generating is disabled until you change this from the placeholder.",
                          systemImage: "exclamationmark.circle")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
                Text("Every generated Kotlin file declares this package. One package for the whole project, because the model files share one namespace.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                outputRow(title: "Kotlin output",
                          path: kotlinOutput,
                          hint: "Where Generate writes the .kt files.")
            } header: {
                Text("Kotlin")
            }

            Section {
                TextField("Module", text: swiftModule, prompt: Text("Optional"))
                    .textFieldStyle(.roundedBorder)

                Picker("Access level", selection: swiftAccessLevel) {
                    Text("Internal").tag(SwiftEmitterConfiguration.AccessLevel.internal)
                    Text("Public").tag(SwiftEmitterConfiguration.AccessLevel.public)
                }

                Toggle("Codable", isOn: swiftFlag(\.codable))
                Toggle("Sendable", isOn: swiftFlag(\.sendable))
                Toggle("Hashable", isOn: swiftFlag(\.hashable))
                Toggle("Equatable", isOn: swiftFlag(\.equatable))
                    .disabled(session.configuration.swift.hashable)
                    .help(session.configuration.swift.hashable
                          ? "Hashable already implies Equatable."
                          : "")

                outputRow(title: "Swift output",
                          path: swiftOutput,
                          hint: "Where Generate writes the .swift files.")
            } header: {
                Text("Swift")
            }

            Section {
                ForEach(ScalarType.allCases, id: \.self) { scalar in
                    LabeledContent(scalar.rawValue) {
                        HStack(spacing: 12) {
                            Text(session.configuration.swift.type(for: scalar))
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(session.configuration.kotlin.mapping(for: scalar).simpleName)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Type mapping")
            } footer: {
                Text("Swift on the left, Kotlin on the right. Note that there is no Int: its width differs between the two platforms, so write Int32 or Int64.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: Output folders

    @ViewBuilder
    private func outputRow(title: String, path: Binding<String>, hint: String) -> some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                Text(path.wrappedValue.isEmpty ? "Not set" : path.wrappedValue)
                    .font(.callout.monospaced())
                    .foregroundStyle(path.wrappedValue.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.head)
                Spacer()
                Button("Choose…") { chooseFolder(into: path) }
                if !path.wrappedValue.isEmpty {
                    Button("Clear") { path.wrappedValue = "" }
                }
            }
        }
        Text(hint + " Stored relative to the project, so it keeps working after a rename and for anyone else who clones the repository.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func chooseFolder(into path: Binding<String>) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        path.wrappedValue = OutputLocation.relativePath(from: session.projectDirectory, to: url)
    }

    // MARK: Bindings

    private var kotlinPackage: Binding<String> {
        Binding(get: { session.configuration.kotlin.package },
                set: { value in session.updateConfiguration { $0.kotlin.package = value } })
    }

    private var kotlinOutput: Binding<String> {
        Binding(get: { session.configuration.kotlin.output ?? "" },
                set: { value in
                    session.updateConfiguration { $0.kotlin.output = value.isEmpty ? nil : value }
                })
    }

    private var swiftOutput: Binding<String> {
        Binding(get: { session.configuration.swift.output ?? "" },
                set: { value in
                    session.updateConfiguration { $0.swift.output = value.isEmpty ? nil : value }
                })
    }

    private var swiftModule: Binding<String> {
        Binding(get: { session.configuration.swift.module ?? "" },
                set: { value in
                    session.updateConfiguration { $0.swift.module = value.isEmpty ? nil : value }
                })
    }

    private var swiftAccessLevel: Binding<SwiftEmitterConfiguration.AccessLevel> {
        Binding(get: { session.configuration.swift.accessLevel },
                set: { value in session.updateConfiguration { $0.swift.accessLevel = value } })
    }

    private func swiftFlag(_ keyPath: WritableKeyPath<SwiftEmitterConfiguration, Bool>) -> Binding<Bool> {
        Binding(get: { session.configuration.swift[keyPath: keyPath] },
                set: { value in session.updateConfiguration { $0.swift[keyPath: keyPath] = value } })
    }
}
