import Foundation

/// "Did you mean …?" suggestions for a misspelled identifier.
///
/// Uses Damerau-Levenshtein so a transposition (`Uesr` for `User`) costs one edit rather
/// than two, which is the most common typo class in hand-written type names.
public enum NameSuggestion {

    /// The closest candidate to `name`, or `nil` when nothing is close enough.
    ///
    /// The threshold scales with the name's length so short names don't match everything:
    /// a three-character name allows one edit, a nine-character name allows three.
    public static func closest(to name: String,
                               among candidates: some Sequence<String>) -> String? {
        guard !name.isEmpty else { return nil }
        let threshold = max(1, min(3, name.count / 3))

        var best: (name: String, distance: Int)?
        for candidate in candidates where candidate != name {
            // A pure case difference is always worth suggesting.
            if candidate.lowercased() == name.lowercased() {
                return candidate
            }
            let distance = editDistance(name, candidate, limit: threshold)
            guard distance <= threshold else { continue }
            if best == nil || distance < best!.distance
                || (distance == best!.distance && candidate < best!.name) {
                best = (candidate, distance)
            }
        }
        return best?.name
    }

    /// Damerau-Levenshtein distance, abandoning early once every cell in a row exceeds
    /// `limit` since callers only care about small distances.
    static func editDistance(_ lhs: String, _ rhs: String, limit: Int = .max) -> Int {
        let a = Array(lhs.unicodeScalars)
        let b = Array(rhs.unicodeScalars)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        if abs(a.count - b.count) > limit { return limit + 1 }

        var previousPrevious = [Int](repeating: 0, count: b.count + 1)
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)

        for i in 1...a.count {
            current[0] = i
            var rowMinimum = current[0]
            for j in 1...b.count {
                let substitutionCost = a[i - 1] == b[j - 1] ? 0 : 1
                var value = min(previous[j] + 1,          // deletion
                                current[j - 1] + 1,       // insertion
                                previous[j - 1] + substitutionCost)
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                    value = min(value, previousPrevious[j - 2] + 1)   // transposition
                }
                current[j] = value
                rowMinimum = min(rowMinimum, value)
            }
            if rowMinimum > limit { return limit + 1 }
            previousPrevious = previous
            previous = current
            current = [Int](repeating: 0, count: b.count + 1)
        }
        return previous[b.count]
    }
}
