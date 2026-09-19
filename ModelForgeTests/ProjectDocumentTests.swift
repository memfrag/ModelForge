//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Testing
import Foundation
import ModelForgeKit
@testable import ModelForge

@Suite("Project document")
@MainActor struct ProjectDocumentTests {

    @Test("A new project starts from the worked example, not an empty file")
    func starterIsPopulated() {
        let document = ProjectDocument()
        #expect(document.sources.count == 1)
        #expect(document.sources[0].name == ProjectLayout.starterFileName)
        #expect(document.sources[0].text.contains("model"))
    }

    @Test("Appending assigns ids that never collide with the ones already in use")
    func appendedIDsAreFresh() {
        let document = makeDocument([("b.model", ""), ("a.model", "")])
        let first = document.appendSource(named: "c.model", text: "")
        let second = document.appendSource(named: "d.model", text: "")

        #expect(Set(document.sources.map(\.id)).count == 4)
        #expect(first != second)
        #expect(!document.sources.dropLast(2).map(\.id).contains(first))
    }

    @Test("Files stay in natural sorted order as they are added and renamed")
    func sourcesAreSorted() {
        let document = makeDocument([("zebra.model", ""), ("alpha.model", "")])
        #expect(document.sources.map(\.name) == ["alpha.model", "zebra.model"])

        document.appendSource(named: "middle.model", text: "")
        #expect(document.sources.map(\.name) == ["alpha.model", "middle.model", "zebra.model"])

        let id = document.sources[0].id
        document.renameSource(id, to: "omega.model")
        #expect(document.sources.map(\.name) == ["middle.model", "omega.model", "zebra.model"])
    }

    @Test("File 10 sorts after file 9, not after file 1")
    func sortingIsNatural() {
        let document = makeDocument([("file10.model", ""), ("file9.model", ""), ("file1.model", "")])
        #expect(document.sources.map(\.name) == ["file1.model", "file9.model", "file10.model"])
    }

    @Test("A name is taken case-insensitively")
    func nameAvailabilityIgnoresCase() {
        let document = makeDocument([("User.model", "")])
        #expect(!document.isNameAvailable("user.model"))
        #expect(!document.isNameAvailable("USER.MODEL"))
        #expect(document.isNameAvailable("other.model"))
    }

    @Test("A file cannot be named after one the bundle owns")
    func reservedNamesAreRefused() {
        let document = makeDocument()
        #expect(!document.isNameAvailable(ProjectLayout.configurationFileName))
        #expect(!document.isNameAvailable(ProjectLayout.manifestFileName))
    }

    @Test("Renaming a file to the name it already has is not a collision")
    func excludingSelfAllowsANoOpRename() {
        let document = makeDocument([("user.model", "")])
        let id = document.sources[0].id
        #expect(!document.isNameAvailable("user.model"))
        #expect(document.isNameAvailable("user.model", excluding: id))
    }

    @Test("Untitled, Untitled 2, Untitled 3")
    func availableNameCountsUp() {
        let document = makeDocument()
        #expect(document.availableName(basedOn: "Untitled") == "Untitled.model")

        document.appendSource(named: "Untitled.model", text: "")
        #expect(document.availableName(basedOn: "Untitled") == "Untitled 2.model")

        document.appendSource(named: "Untitled 2.model", text: "")
        #expect(document.availableName(basedOn: "Untitled") == "Untitled 3.model")
    }

    @Test("A name offered with an extension does not get a second one")
    func availableNameStripsTheExtension() {
        let document = makeDocument()
        #expect(document.availableName(basedOn: "Untitled.model") == "Untitled.model")
    }

    @Test("Removing a file removes it from lookup too")
    func removingAFile() {
        let document = makeDocument([("a.model", "x"), ("b.model", "y")])
        let id = document.sources[0].id
        document.removeSource(id)

        #expect(document.sources.map(\.name) == ["b.model"])
        #expect(document[id] == nil)
    }

    @Test("Editing text that does not exist is ignored rather than crashing")
    func updatingAnUnknownFileIsHarmless() {
        let document = makeDocument([("a.model", "x")])
        document.updateText("y", for: SourceFileID(99))
        document.renameSource(SourceFileID(99), to: "b.model")
        #expect(document.sources.map(\.text) == ["x"])
        #expect(document.sources.map(\.name) == ["a.model"])
    }

    @Test("The compiler sees the same names and ids the file list shows")
    func sourceFilesMirrorSources() {
        let document = makeDocument([("a.model", "one"), ("b.model", "two")])
        #expect(document.sourceFiles.map(\.name) == document.sources.map(\.name))
        #expect(document.sourceFiles.map(\.id) == document.sources.map(\.id))
        #expect(document.sourceFiles.map(\.text) == ["one", "two"])
    }
}
