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
    private static let swiftOrange = NSColor(srgbRed: 240 / 255, green: 81 / 255,
                                             blue: 56 / 255, alpha: 1)

    /// The bird with its colour baked into the image rather than applied around it.
    ///
    /// A menu draws an SF Symbol as a template — it takes the shape and paints it in the
    /// menu's own label colour — so `foregroundStyle` is discarded there and the bird comes
    /// out white next to a Kotlin mark that kept its gradient. A palette configuration puts
    /// the colour inside the image, and `isTemplate = false` stops the menu repainting it.
    private static func bird(size: CGFloat) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: size, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [swiftOrange]))
        guard let image = NSImage(systemSymbolName: "swift",
                                  accessibilityDescription: "Swift")?
            .withSymbolConfiguration(configuration) else { return nil }
        image.isTemplate = false
        return image
    }

    var body: some View {
        switch language {
        case .swift:
            if let bird = Self.bird(size: size) {
                Image(nsImage: bird)
                    .frame(width: size + 3, height: size + 3)
            } else {
                // No such symbol, which would mean a very old system. The word alone still
                // names the language.
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: size))
                    .frame(width: size + 3, height: size + 3)
            }

        case .kotlin:
            // Artwork rather than a symbol, so it keeps its own gradient and ignores any
            // tint around it.
            //
            // Drawn a point smaller than the bird's box rather than the same. The mark is
            // a solid shape and the bird is an open one, so at matching sizes the Kotlin
            // one carries more ink and reads as the larger of the two.
            Image(.kotlin)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
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

/// One option in the preview selector, with its mark.
///
/// `Both` has no language of its own, so it takes a symbol describing the layout — two
/// panes, one above the other — rather than borrowing one of the two marks.
struct PreviewChoiceLabel: View {

    let choice: PreviewChoice

    var body: some View {
        Label {
            Text(choice.displayName)
        } icon: {
            if let language = choice.language {
                LanguageIcon(language: language, size: 12)
            } else {
                Image(systemName: "rectangle.split.1x2")
            }
        }
    }
}
