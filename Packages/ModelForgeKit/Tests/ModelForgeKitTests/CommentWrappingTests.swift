import Testing
@testable import ModelForgeKit

@Suite("Comment wrapping")
struct CommentWrappingTests {

    private func wrap(_ text: String, prefix: String = "/// ", indent: Int = 0) -> [String] {
        CommentWrapping.lines(for: text, prefix: prefix, indent: indent)
    }

    @Test("A line that fits is left alone")
    func aShortLine() {
        #expect(wrap("A user.") == ["/// A user."])
    }

    @Test("A long line is broken at a space, and every piece fits")
    func aLongLine() {
        let text = "Free-form HTML describing the opening hours. Often defers to a petrol station's hours."
        let result = wrap(text)

        #expect(result.count == 2)
        #expect(result.allSatisfy { $0.count <= CommentWrapping.columnLimit })
        #expect(result[0].hasPrefix("/// "))
        #expect(result[1].hasPrefix("/// "))
    }

    @Test("Nothing is lost or added but the markers")
    func wrappingPreservesTheWords() {
        let text = "Despite the name, this frequently holds a street address rather than a postal code."
        let words = text.split(separator: " ").map(String.init)
        let rejoined = wrap(text)
            .map { $0.replacingOccurrences(of: "/// ", with: "") }
            .joined(separator: " ")

        #expect(rejoined.split(separator: " ").map(String.init) == words)
    }

    @Test("Indentation counts against the limit")
    func indentationIsCharged() {
        // A comment that fits at the top level does not necessarily fit as a field's, two
        // levels in.
        let text = String(repeating: "word ", count: 14).trimmingCharacters(in: .whitespaces)

        for indent in [0, 4, 8, 12] {
            let result = CommentWrapping.lines(for: text, prefix: "/// ", indent: indent)
            #expect(result.allSatisfy { indent + $0.count <= CommentWrapping.columnLimit })
        }
    }

    @Test("Each source line is wrapped on its own, not reflowed into the next")
    func linesAreNotReflowed() {
        // A break someone put in a doc comment is usually deliberate.
        #expect(wrap("First.") == ["/// First."])
        #expect(wrap("Second.") == ["/// Second."])
    }

    @Test("A blank line keeps its marker and gains no trailing space")
    func blankLines() {
        #expect(wrap("") == ["///"])
        #expect(wrap("   ") == ["///"])
        #expect(CommentWrapping.lines(for: "", prefix: " * ", indent: 0) == [" *"])
    }

    @Test("A word too long to fit is left whole rather than broken")
    func anUnbreakableWord() {
        // Breaking one would break an identifier, a URL or a symbol reference.
        let long = String(repeating: "A", count: 120)
        let result = wrap(long)

        #expect(result == ["/// " + long])
    }

    @Test("A long word after short ones starts its own line")
    func anUnbreakableWordAfterOthers() {
        let long = String(repeating: "A", count: 100)
        let result = wrap("See \(long) for details.")

        #expect(result[0] == "/// See")
        #expect(result[1] == "/// " + long)
        #expect(result[2] == "/// for details.")
    }

    @Test("Indented past the limit, it gives up rather than emitting a word per line")
    func noRoomToWrap() {
        let result = CommentWrapping.lines(for: "some text here", prefix: "/// ", indent: 200)
        #expect(result == ["/// some text here"])
    }

    @Test("Runs of spaces do not become empty words")
    func collapsedWhitespace() {
        #expect(wrap("a     b") == ["/// a b"])
    }

    @Test("The one-line Kotlin form is only offered when it fits")
    func fitsAnswersForTheWholeLine() {
        #expect(CommentWrapping.fits("/** Short. */", indent: 4))
        #expect(!CommentWrapping.fits("/** " + String(repeating: "x", count: 80) + " */", indent: 4))
        // The indent is part of the line.
        #expect(CommentWrapping.fits(String(repeating: "x", count: 76), indent: 4))
        #expect(!CommentWrapping.fits(String(repeating: "x", count: 77), indent: 4))
    }
}
