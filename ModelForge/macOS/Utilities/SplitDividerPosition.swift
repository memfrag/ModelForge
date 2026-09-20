//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI
import AppKit

/// Makes the enclosing split view remember where its divider was put.
///
/// Selecting Project Settings or the Type Graph replaces the whole detail column, so the
/// `HSplitView` around the editor and the previews is torn down and built again on the way
/// back. A fresh one divides itself from its children's ideal widths, which throws away
/// wherever the divider had been dragged to — the editor appears to resize itself for no
/// reason anyone in the window did.
///
/// `NSSplitView` already solves this: give it an autosave name and AppKit stores the
/// position and restores it into the next one with the same name. That also carries the
/// divider across launches, which is what anyone who has moved it would expect anyway.
///
/// Attached as a background rather than wrapped around anything, so it takes no space and
/// changes no layout.
struct SplitDividerPosition: NSViewRepresentable {

    /// Unique per split view, and stable across launches.
    let name: String

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ view: NSView, context: Context) {
        // Next turn of the run loop: on the first pass the view is not in the hierarchy
        // yet, so there is no split view above it to find.
        Task { @MainActor in
            guard let split = view.enclosingSplitView, split.autosaveName != name else { return }
            split.autosaveName = name
        }
    }
}

private extension NSView {

    /// The nearest split view this one sits inside.
    var enclosingSplitView: NSSplitView? {
        var candidate: NSView? = superview
        while let current = candidate {
            if let split = current as? NSSplitView { return split }
            candidate = current.superview
        }
        return nil
    }
}
