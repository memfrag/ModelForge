//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI
import AppKit
import SensibleStyling
import ModelForgeKit

extension Notification.Name {
    /// Posted when any editor colour changes, so open text views re-highlight.
    static let editorThemeChanged = Notification.Name("editorThemeChanged")
}

/// Colours for the DSL editor and the generated-code previews.
///
/// One theme for all three languages. The highlighter emits `HighlightKind` values rather
/// than language-specific ones precisely so a keyword looks the same whether it is `model`,
/// `struct` or `data class`.
///
/// Defaults come in light and dark pairs drawn from the Tailwind palette that
/// `SensibleStyling` already provides, wrapped in a dynamic `NSColor` so switching
/// appearance needs no re-highlight.
@Observable @MainActor final class EditorTheme {

    private var overrides: [HighlightKind: Color] = [:]

    init() {
        for kind in HighlightKind.allCases {
            if let hex = UserDefaults.standard.string(forKey: Self.key(kind)),
               let color = Color(hexRGBA: hex) {
                overrides[kind] = color
            }
        }
    }

    // MARK: Colours

    /// The colour to draw `kind` in: the user's override if there is one, else the default.
    func nsColor(for kind: HighlightKind) -> NSColor {
        if let color = overrides[kind] { return NSColor(color) }
        return Self.defaultColor(for: kind)
    }

    func isCustomized(_ kind: HighlightKind) -> Bool {
        overrides[kind] != nil
    }

    var hasCustomColors: Bool { !overrides.isEmpty }

    /// A binding for a colour well. Reads the override, or the resolved default.
    func binding(for kind: HighlightKind) -> Binding<Color> {
        Binding(
            get: { self.overrides[kind] ?? Color(nsColor: Self.defaultColor(for: kind)) },
            set: { self.setColor($0, for: kind) }
        )
    }

    func setColor(_ color: Color, for kind: HighlightKind) {
        overrides[kind] = color
        UserDefaults.standard.set(NSColor(color).hexRGBA, forKey: Self.key(kind))
        notifyChanged()
    }

    func reset(_ kind: HighlightKind) {
        overrides.removeValue(forKey: kind)
        UserDefaults.standard.removeObject(forKey: Self.key(kind))
        notifyChanged()
    }

    func resetToDefaults() {
        for kind in HighlightKind.allCases {
            UserDefaults.standard.removeObject(forKey: Self.key(kind))
        }
        overrides.removeAll()
        notifyChanged()
    }

    private func notifyChanged() {
        NotificationCenter.default.post(name: .editorThemeChanged, object: nil)
    }

    private static func key(_ kind: HighlightKind) -> String {
        "editorTheme.\(kind.rawValue)"
    }

    // MARK: Defaults

    nonisolated static func defaultColor(for kind: HighlightKind) -> NSColor {
        switch kind {
        case .keyword: dynamic(light: .Sensible.purple700, dark: .Sensible.purple400)
        case .declarationName: dynamic(light: .Sensible.indigo700, dark: .Sensible.indigo400)
        case .fieldName: .labelColor
        case .typeName: dynamic(light: .Sensible.sky700, dark: .Sensible.sky400)
        case .enumCase: dynamic(light: .Sensible.orange700, dark: .Sensible.orange400)
        case .attribute: dynamic(light: .Sensible.rose700, dark: .Sensible.rose400)
        case .string: dynamic(light: .Sensible.emerald700, dark: .Sensible.emerald400)
        case .number: dynamic(light: .Sensible.amber700, dark: .Sensible.amber400)
        case .comment: dynamic(light: .Sensible.slate400, dark: .Sensible.slate500)
        case .docComment: dynamic(light: .Sensible.teal700, dark: .Sensible.teal500)
        case .punctuation: .tertiaryLabelColor
        }
    }

    /// A colour that resolves differently in light and dark appearance, so the editor
    /// adapts without re-running the highlighter.
    private nonisolated static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
    }
}

// MARK: - Display names

extension HighlightKind {

    var displayName: String {
        switch self {
        case .keyword: "Keyword"
        case .declarationName: "Declaration Name"
        case .fieldName: "Field Name"
        case .typeName: "Type Name"
        case .enumCase: "Enum Case"
        case .attribute: "Attribute"
        case .string: "String"
        case .number: "Number"
        case .comment: "Comment"
        case .docComment: "Documentation"
        case .punctuation: "Punctuation"
        }
    }
}

// MARK: - Colour <-> hex (RRGGBBAA)

extension Color {

    init?(hexRGBA hex: String) {
        var text = hex
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 8, let value = UInt32(text, radix: 16) else { return nil }
        self = Color(.sRGB,
                     red: Double((value >> 24) & 0xff) / 255,
                     green: Double((value >> 16) & 0xff) / 255,
                     blue: Double((value >> 8) & 0xff) / 255,
                     opacity: Double(value & 0xff) / 255)
    }
}

extension NSColor {

    var hexRGBA: String {
        let color = usingColorSpace(.sRGB) ?? self
        return String(format: "%02X%02X%02X%02X",
                      UInt32((color.redComponent * 255).rounded()),
                      UInt32((color.greenComponent * 255).rounded()),
                      UInt32((color.blueComponent * 255).rounded()),
                      UInt32((color.alphaComponent * 255).rounded()))
    }
}
