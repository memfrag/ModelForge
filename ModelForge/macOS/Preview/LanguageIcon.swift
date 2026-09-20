//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI
import ModelForgeKit

/// The mark for one of the two languages, for putting in front of its name.
///
/// Only one of them is a symbol: SF Symbols carries the Swift bird, and nothing for Kotlin,
/// so Kotlin's comes from the asset catalogue as artwork in its own colours. The Swift bird
/// is tinted to match, so the two read as a pair rather than as a symbol next to a logo.
struct LanguageIcon: View {

    let language: Language
    var size: CGFloat = 12

    /// The Swift brand orange, so the bird is not simply the label colour with wings.
    private static let swiftOrange = Color(red: 240 / 255, green: 81 / 255, blue: 56 / 255)

    var body: some View {
        switch language {
        case .swift:
            Image(systemName: "swift")
                .font(.system(size: size))
                .foregroundStyle(Self.swiftOrange)
                .frame(width: size + 3, height: size + 3)

        case .kotlin:
            // Artwork rather than a symbol, so it keeps its own gradient and ignores any
            // tint around it.
            Image(.kotlin)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size + 1, height: size + 1)
        }
    }
}

/// A language's name with its mark in front of it.
struct LanguageLabel: View {

    let language: Language
    var size: CGFloat = 12

    var body: some View {
        HStack(spacing: 4) {
            LanguageIcon(language: language, size: size)
            Text(language.displayName)
        }
    }
}
