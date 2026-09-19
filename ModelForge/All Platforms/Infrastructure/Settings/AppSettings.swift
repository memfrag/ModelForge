//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI
import KeyValueStore

// MARK: - AppSettings

/// A container for application-wide user settings.
///
/// `AppSettings` provides observable properties that represent user preferences
/// and persists them using an underlying key–value store.
/// It is designed to be injected into SwiftUI views and other components
/// that depend on reactive settings.
///
@Observable @MainActor public final class AppSettings {

    // MARK: Key

    /// The keys used to store and retrieve settings from the underlying store.
    public enum Key: String {
        /// The preferred color scheme for the app.
        case colorScheme
        /// How long to wait after a keystroke before recompiling the previews.
        case previewDebounceMilliseconds
        /// Point size of the editor and preview font.
        case editorFontSize
        /// Whether the preview column shows one language or both.
        case previewLayout
        /// Whether the embedded MCP server accepts connections.
        case mcpServerEnabled
        /// The port the embedded MCP server listens on.
        case mcpServerPort

        // <-- (1 / 3) Add key for new property here
    }

    // MARK: Properties

    /// The app's current color scheme preference.
    public var colorScheme: AppColorScheme {
        didSet {
            store.save(colorScheme, for: .colorScheme)
        }
    }

    /// How long to wait after a keystroke before recompiling.
    ///
    /// Short enough to feel immediate, long enough that a fast typist is not recompiling
    /// on every character. The compile itself takes about a millisecond at the sizes this
    /// tool targets, so this is about restraint rather than throughput.
    public var previewDebounceMilliseconds: Int {
        didSet {
            store.save(previewDebounceMilliseconds, for: .previewDebounceMilliseconds)
        }
    }

    /// Point size of the monospaced font in the editor and previews.
    public var editorFontSize: Double {
        didSet {
            store.save(editorFontSize, for: .editorFontSize)
        }
    }

    /// Whether the preview column shows one language at a time or both stacked.
    public var previewLayout: PreviewLayout {
        didSet {
            store.save(previewLayout, for: .previewLayout)
        }
    }

    /// Whether the embedded MCP server is listening.
    ///
    /// Off by default: it opens a local port, which is the user's decision to make.
    public var mcpServerEnabled: Bool {
        didSet {
            store.save(mcpServerEnabled, for: .mcpServerEnabled)
        }
    }

    /// The port the embedded MCP server binds, on 127.0.0.1 only.
    public var mcpServerPort: Int {
        didSet {
            store.save(mcpServerPort, for: .mcpServerPort)
        }
    }

    // <-- (2 / 3) Add property for new property here

    // MARK: Setup

    /// The key–value store that backs this settings container.
    @ObservationIgnored
    private let store: AnyKeyValueStore<AppSettings.Key>

    /// Creates a new instance of `AppSettings`.
    ///
    /// - Parameter store: The store used to persist values. If `nil`,
    ///   defaults to a `UserDefaults`-backed store.
    ///
    public init(store: AnyKeyValueStore<AppSettings.Key>? = nil) {
        self.store = store ?? .defaultStore
        colorScheme = self.store.load(.colorScheme, default: .system)
        previewDebounceMilliseconds = self.store.load(.previewDebounceMilliseconds, default: 300)
        editorFontSize = self.store.load(.editorFontSize, default: 13)
        previewLayout = self.store.load(.previewLayout, default: .single)
        mcpServerEnabled = self.store.load(.mcpServerEnabled, default: false)
        mcpServerPort = self.store.load(.mcpServerPort, default: 8124)

        // <-- (3 / 3) Add initializer for new property here.
    }
}
