//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Testing
import Foundation
import ModelForgeKit
@testable import ModelForge

/// How the embedded MCP server finds the window an agent means.
///
/// Every session built in a test is an unsaved one, so they are all called "Untitled" —
/// which is exactly the case that exercises the ambiguity path, and is worth knowing about
/// in its own right: an agent cannot address two unsaved projects apart.
@Suite("Open project registry")
@MainActor struct OpenProjectRegistryTests {

    @Test("Registering the same session twice registers it once")
    func registrationIsIdempotent() {
        let registry = OpenProjectRegistry()
        let session = makeSession()

        registry.register(session)
        registry.register(session)

        #expect(registry.sessions.count == 1)
    }

    @Test("Closing a window takes its project out of the registry")
    func deregistering() {
        let registry = OpenProjectRegistry()
        let first = makeSession()
        let second = makeSession()
        registry.register(first)
        registry.register(second)

        registry.deregister(first)

        #expect(registry.sessions.count == 1)
        #expect(registry.sessions[0] === second)
    }

    @Test("A blank query is refused rather than guessed at")
    func aBlankQueryIsRefused() {
        let registry = OpenProjectRegistry()
        registry.register(makeSession())

        #expect(throws: MCPToolError.self) {
            try registry.session(matching: "   ")
        }
    }

    @Test("With nothing open, the error says how to open something")
    func nothingOpen() {
        let registry = OpenProjectRegistry()
        do {
            _ = try registry.session(matching: "Anything")
            Issue.record("expected the lookup to fail")
        } catch {
            #expect(error.message.contains("No projects are open"))
            #expect(error.message.contains("open_project"))
        }
    }

    @Test("An exact name matches")
    func matchingByName() throws {
        let registry = OpenProjectRegistry()
        let session = makeSession()
        registry.register(session)

        #expect(try registry.session(matching: "Untitled") === session)
        #expect(try registry.session(matching: "untitled") === session)
    }

    @Test("A prefix matches when only one project could be meant")
    func matchingByPrefix() throws {
        let registry = OpenProjectRegistry()
        let session = makeSession()
        registry.register(session)

        #expect(try registry.session(matching: "Unt") === session)
    }

    @Test("A name that matches nothing lists what is open")
    func noMatchListsWhatIsOpen() {
        let registry = OpenProjectRegistry()
        registry.register(makeSession())

        do {
            _ = try registry.session(matching: "Payments")
            Issue.record("expected the lookup to fail")
        } catch {
            #expect(error.message.contains("Payments"))
            #expect(error.message.contains("Untitled"))
        }
    }

    @Test("A name that matches several is refused, naming them")
    func ambiguityIsRefused() {
        let registry = OpenProjectRegistry()
        registry.register(makeSession())
        registry.register(makeSession())

        do {
            _ = try registry.session(matching: "Unt")
            Issue.record("expected the lookup to fail")
        } catch {
            #expect(error.message.contains("matches several open projects"))
            #expect(error.message.contains("bundle's path"))
        }
    }

    @Test("A project that has never been saved is called Untitled")
    func unsavedProjectsAreUntitled() {
        #expect(makeSession().projectName == "Untitled")
    }
}
