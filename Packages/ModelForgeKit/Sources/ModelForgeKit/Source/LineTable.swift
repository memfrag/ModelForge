import Foundation

/// Maps UTF-16 offsets to 1-based line and column numbers.
///
/// Built once per source file. Lookup is a binary search over the line starts, which
/// keeps diagnostics cheap even when a file produces many of them.
public struct LineTable: Sendable, Hashable {

    /// UTF-16 offset of the first character of each line. Always starts with 0.
    public let lineStarts: [Int]

    /// Total length of the source in UTF-16 code units.
    public let length: Int

    public init(utf16 units: [UInt16]) {
        var starts = [0]
        for index in units.indices where units[index] == 0x0A {
            starts.append(index + 1)
        }
        lineStarts = starts
        length = units.count
    }

    public var lineCount: Int {
        lineStarts.count
    }

    /// The 1-based line containing `offset`.
    public func line(containing offset: Int) -> Int {
        let clamped = min(max(offset, 0), length)
        var low = 0
        var high = lineStarts.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if lineStarts[mid] <= clamped {
                low = mid
            } else {
                high = mid - 1
            }
        }
        return low + 1
    }

    /// The UTF-16 range of `line`, excluding its terminating newline.
    /// Returns an empty range at the end of the file for an out-of-bounds line.
    public func range(ofLine line: Int) -> Range<Int> {
        guard line >= 1, line <= lineStarts.count else {
            return length..<length
        }
        let start = lineStarts[line - 1]
        let end = line < lineStarts.count ? lineStarts[line] - 1 : length
        return start..<max(start, end)
    }
}
