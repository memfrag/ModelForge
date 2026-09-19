//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation

/// A record of what Generate last wrote, and where.
///
/// Without this, renaming `user.model` to `account.model` would leave a stale `User.swift`
/// behind in the output folder — and it would keep compiling into the iOS and Android apps
/// as a type nobody declares any more. On each run, anything listed here that this run did
/// not produce is deleted.
///
/// Only paths ModelForge itself wrote are ever recorded, so hand-written files sharing an
/// output folder are never at risk.
nonisolated struct GenerationManifest: Codable, Sendable, Hashable {

    /// Paths, relative to the project bundle, written on the last run.
    var swiftFiles: [String]
    var kotlinFiles: [String]

    init(swiftFiles: [String] = [], kotlinFiles: [String] = []) {
        self.swiftFiles = swiftFiles.sorted()
        self.kotlinFiles = kotlinFiles.sorted()
    }

    var isEmpty: Bool {
        swiftFiles.isEmpty && kotlinFiles.isEmpty
    }

    static func decoded(from data: Data) -> GenerationManifest {
        // A missing or unreadable manifest is not worth failing a project load over; the
        // worst case is one round of stale files surviving.
        (try? JSONDecoder().decode(GenerationManifest.self, from: data)) ?? GenerationManifest()
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}
