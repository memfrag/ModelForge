//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import ModelForgeKit

/// What the preview column is showing, as one choice.
///
/// The two pieces behind it are stored separately and for good reason — which language you
/// were last looking at belongs to the window, and whether you want both at once is a
/// preference that should outlive it — but as a control they are one three-way switch, and
/// splitting them across a picker and a settings pane is how "show both" ended up somewhere
/// nobody would find it.
enum PreviewChoice: String, CaseIterable, Identifiable, Hashable {
    case swift
    case kotlin
    case both

    var id: Self { self }

    var displayName: String {
        switch self {
        case .swift: Language.swift.displayName
        case .kotlin: Language.kotlin.displayName
        case .both: "Both"
        }
    }

    init(layout: PreviewLayout, language: Language) {
        switch layout {
        case .both: self = .both
        case .single: self = language == .kotlin ? .kotlin : .swift
        }
    }

    var layout: PreviewLayout {
        self == .both ? .both : .single
    }

    /// The language to select when collapsing back to one pane. `nil` for `.both`, which
    /// leaves whichever language was last chosen alone.
    var language: Language? {
        switch self {
        case .swift: .swift
        case .kotlin: .kotlin
        case .both: nil
        }
    }
}

import SwiftUI

extension PreviewChoice {

    /// Reading combines the window's language with the app's layout; setting writes both
    /// back. Lives here rather than in the view so the toolbar and the preview column
    /// cannot drift on what the control means.
    @MainActor
    static func binding(session: ProjectSession, settings: AppSettings) -> Binding<PreviewChoice> {
        Binding(
            get: { PreviewChoice(layout: settings.previewLayout,
                                 language: session.previewLanguage) },
            set: { new in
                settings.previewLayout = new.layout
                if let language = new.language { session.previewLanguage = language }
            })
    }
}
