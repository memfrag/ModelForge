import Foundation

/// One `.model` file's text, ready to compile.
///
/// A value type so it can cross an actor boundary to a background compile without any
/// locking. The app snapshots its editors into these on every debounce tick.
public struct SourceFile: Sendable, Hashable, Identifiable {

    public let id: SourceFileID

    /// The file's name inside the project bundle, for example `user.model`. Used in
    /// diagnostics and to derive generated file names.
    public let name: String

    public let text: String

    /// The text as UTF-16 code units. The lexer scans this directly.
    public let utf16: [UInt16]

    public let lineTable: LineTable

    public init(id: SourceFileID, name: String, text: String) {
        self.id = id
        self.name = name
        self.text = text
        let units = Array(text.utf16)
        self.utf16 = units
        self.lineTable = LineTable(utf16: units)
    }

    /// The file name without its extension, for example `user` from `user.model`.
    public var stem: String {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else {
            return name
        }
        return String(name[name.startIndex..<dot])
    }

    public func location(at offset: Int) -> SourceLocation {
        SourceLocation(offset: offset, in: lineTable)
    }

    public func range(from start: Int, to end: Int) -> SourceRange {
        SourceRange(file: id, start: location(at: start), end: location(at: end))
    }

    /// The text of `line`, excluding its newline. Used when rendering diagnostics.
    public func text(ofLine line: Int) -> String {
        let range = lineTable.range(ofLine: line)
        guard range.lowerBound < utf16.count else { return "" }
        let slice = utf16[range.lowerBound..<min(range.upperBound, utf16.count)]
        return String(decoding: Array(slice), as: UTF16.self)
    }

    public static func == (lhs: SourceFile, rhs: SourceFile) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.text == rhs.text
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(name)
        hasher.combine(text)
    }
}
