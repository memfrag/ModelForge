//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation

/// How the preview column is arranged.
///
/// Three columns of code are cramped below about 1400 points, so one language at a time is
/// the default and both stacked is there for when you want to compare them.
public enum PreviewLayout: String, Codable, Sendable, CaseIterable, Identifiable {
    /// One language, chosen with the picker in the preview header.
    case single
    /// Swift above Kotlin.
    case both

    public var id: Self { self }

    public var description: String {
        switch self {
        case .single: "One language"
        case .both: "Swift and Kotlin"
        }
    }
}
