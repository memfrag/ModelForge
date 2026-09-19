//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation

/// Notices when the project bundle changes on disk.
///
/// A ModelForge project lives in a git repository, so `git checkout` rewriting the model
/// files under an open window is an ordinary thing to happen — and SwiftUI holds the
/// document in memory and would never notice.
///
/// Our own saves also trip the watcher, so writes are ignored for a moment after one.
@MainActor final class ProjectWatcher {

    // Torn down from `deinit`, which cannot hop to the main actor.
    private nonisolated(unsafe) var stream: FSEventStreamRef?
    private let onChange: () -> Void
    private var suppressUntil: Date = .distantPast

    /// How long after our own save to keep ignoring events.
    private static let selfWriteGrace: TimeInterval = 1.0

    init?(url: URL, onChange: @escaping () -> Void) {
        self.onChange = onChange

        let context = UnsafeMutablePointer<FSEventStreamContext>.allocate(capacity: 1)
        context.initialize(to: FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil))
        defer {
            context.deinitialize(count: 1)
            context.deallocate()
        }

        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<ProjectWatcher>.fromOpaque(info).takeUnretainedValue()
            DispatchQueue.main.async {
                MainActor.assumeIsolated { watcher.handleEvent() }
            }
        }

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            context,
            [url.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.3,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        ) else {
            return nil
        }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
    }

    deinit {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }

    /// Call before saving so the resulting events are not mistaken for someone else's edit.
    func suppressSelfWrites() {
        suppressUntil = Date().addingTimeInterval(Self.selfWriteGrace)
    }

    private func handleEvent() {
        guard Date() >= suppressUntil else { return }
        onChange()
    }
}
