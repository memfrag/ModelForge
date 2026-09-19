//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI
import ModelForgeKit

/// A quick reference for the DSL.
///
/// Written as views rather than rendered Markdown so the examples can be highlighted with
/// the same code view the editor uses — a reference that looks like the editor is easier
/// to map onto what you are typing.
public struct HelpWindow: Scene {

    public static let windowID = "help"

    public var body: some Scene {
        Window("ModelForge Language Reference", id: Self.windowID) {
            HelpContent()
                .frame(minWidth: 640, minHeight: 480)
                // Every scene needs the environment applied to it: a window opened from
                // the menu bar is not a descendant of the document window.
                .appEnvironment(.default)
        }
        .commandsRemoved()
        .defaultPosition(.center)
        .defaultSize(width: 760, height: 680)
        .windowResizability(.contentMinSize)
    }
}

private struct HelpContent: View {

    @Environment(EditorTheme.self) private var theme
    @Environment(AppSettings.self) private var settings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                section("Models", """
                A model becomes a Swift struct and a Kotlin data class.
                """) {
                    """
                    /// A registered user.
                    model User {
                        id: UUID
                        name: String
                        email: String?
                    }
                    """
                }

                section("Types", """
                Scalars: String, Bool, Int32, Int64, Float, Double, Decimal, UUID, URL, \
                Date, Instant, Duration.

                There is deliberately no Int. Its width differs between Swift and Kotlin, \
                so a server-issued identifier could decode on iOS and overflow on Android \
                with nothing in the schema to warn you.
                """) {
                    """
                    model Container {
                        tags: [String]
                        unique: Set<String>
                        metadata: Map<String, String>
                        maybe: String?
                        nested: [User?]
                    }
                    """
                }

                section("Enums", """
                The constant is renamed to suit each platform, but the value on the wire \
                stays the name you wrote.
                """) {
                    """
                    enum UserStatus {
                        active
                        suspended
                        @json("gone")
                        deleted
                    }
                    """
                }

                section("Enums that may grow", """
                A closed enum fails the whole payload when a backend sends a case this \
                build has never heard of. @extensible keeps the raw value instead and \
                round-trips it untouched, on both platforms. The cost is that you can no \
                longer switch exhaustively — which an enum that may grow could not honestly \
                offer anyway. Use it for anything a server owns.
                """) {
                    """
                    @extensible
                    enum UserStatus {
                        active
                        suspended
                    }
                    """
                }

                section("Unions", """
                A union becomes a Swift enum with associated values and a Kotlin sealed \
                interface. On the wire it is tagged in place: the discriminator sits \
                beside the payload's own fields.

                A payload must be a model, and it may not contain a field named the same \
                as the discriminator.
                """) {
                    """
                    @discriminator("kind")
                    union PaymentMethod {
                        card(Card)
                        applePay(ApplePay)
                    }
                    """
                }

                section("Defaults", """
                A default means the key may be absent from the payload. Both platforms \
                decode a value that omits it — which is what makes adding a defaulted \
                field a compatible change.
                """) {
                    """
                    model Project {
                        name: String
                        archived: Bool = false
                        retries: Int32 = 0
                        tags: [String] = []
                        status: Status = .active
                        note: String? = null
                    }
                    """
                }

                section("Identity", """
                @identifiable conforms a model to Swift's Identifiable, using its id field. \
                Name another field to use that instead, and a bridging id property is \
                generated for you. Swift only — Kotlin has no equivalent.
                """) {
                    """
                    @identifiable
                    model User {
                        id: UUID
                        name: String
                    }

                    @identifiable("code")
                    model Country {
                        code: String
                        name: String
                    }
                    """
                }

                section("Attributes", """
                @json renames a field or case on the wire. @transient keeps a field out of \
                serialization entirely and needs a default. @deprecated carries through to \
                both platforms. @discriminator sets a union's tag key.
                """) {
                    """
                    model User {
                        @json("user_id")
                        id: UUID

                        @deprecated("Use displayName")
                        username: String?

                        @transient
                        isSelected: Bool = false
                    }
                    """
                }

                section("Projects", """
                Every .model file in a project shares one namespace, so types refer to \
                each other with no import. Each file generates one Swift file and one \
                Kotlin file, named after it.
                """, code: nil)
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func section(_ title: String,
                         _ body: String,
                         code: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.title3.weight(.semibold))
            Text(body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let code {
                DSLSnippet(code: code, theme: theme, fontSize: settings.editorFontSize)
            }
        }
    }

    private func section(_ title: String,
                         _ body: String,
                         @SnippetBuilder code: () -> String) -> some View {
        section(title, body, code: code())
    }
}

@resultBuilder
private enum SnippetBuilder {
    static func buildBlock(_ code: String) -> String { code }
}

/// A short, non-editable DSL example, highlighted by the same lexer as the editor.
private struct DSLSnippet: View {

    let code: String
    let theme: EditorTheme
    let fontSize: Double

    var body: some View {
        Text(attributed)
            .textSelection(.enabled)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 8))
    }

    private var attributed: AttributedString {
        let file = SourceFile(id: SourceFileID(0), name: "example.model", text: code)
        var bag = DiagnosticBag()
        let tokens = Lexer.tokenize(file, diagnostics: &bag)

        var result = AttributedString(code)
        result.font = .system(size: fontSize, design: .monospaced)

        let units = Array(code.utf16)
        for span in DSLHighlightClassifier.spans(for: tokens) {
            guard span.range.upperBound <= units.count else { continue }
            guard let lower = AttributedString.Index(
                    String.Index(utf16Offset: span.range.lowerBound, in: code),
                    within: result),
                  let upper = AttributedString.Index(
                    String.Index(utf16Offset: span.range.upperBound, in: code),
                    within: result) else { continue }
            result[lower..<upper].foregroundColor = Color(nsColor: theme.nsColor(for: span.kind))
        }
        return result
    }
}
