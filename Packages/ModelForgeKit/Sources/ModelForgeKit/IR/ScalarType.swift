import Foundation

/// The built-in scalar types.
///
/// Note what is missing: **there is no `Int`**. The proposal's §6.1 mapped it to Swift
/// `Int` (64-bit) and Kotlin `Int` (32-bit), so an identifier above 2^31 would decode
/// happily on iOS and overflow on Android with nothing in the schema to warn you. No type
/// in this language may have a platform-dependent width, so callers write `Int32` or
/// `Int64` and get exactly that on both platforms. `Int` is recognised only to reject it
/// with a fix-it.
public enum ScalarType: String, Sendable, Hashable, CaseIterable {
    case string = "String"
    case bool = "Bool"
    case int32 = "Int32"
    case int64 = "Int64"
    case float = "Float"
    case double = "Double"
    case decimal = "Decimal"
    case uuid = "UUID"
    case url = "URL"
    case date = "Date"
    case instant = "Instant"
    case duration = "Duration"

    /// The name that is rejected outright, with `Int32`/`Int64` offered instead.
    public static let rejectedIntegerName = "Int"

    public var isNumeric: Bool {
        switch self {
        case .int32, .int64, .float, .double, .decimal: true
        default: false
        }
    }

    public var isIntegral: Bool {
        self == .int32 || self == .int64
    }

    public var isFloatingPoint: Bool {
        switch self {
        case .float, .double, .decimal: true
        default: false
        }
    }

    /// Whether the two platforms need generated coders to agree on this type's wire
    /// representation.
    ///
    /// Each of these is a real incompatibility, found by encoding the same value on both
    /// platforms and comparing:
    ///
    /// - `Instant`: Swift's `Date` encodes as a number of seconds from 2001, kotlinx
    ///   writes an ISO-8601 string. Swift cannot decode Kotlin's payload at all.
    /// - `Duration`: Swift encodes a two-element component array, kotlinx writes `PT1M30S`.
    /// - `Date`: Kotlin's usual answer, `kotlinx.datetime.LocalDate`, is a dependency the
    ///   project may not have — and Swift has no date-only type at all.
    /// - `Decimal`: kotlinx has no serializer for `BigDecimal`, so the generated Kotlin
    ///   does not even compile.
    ///
    /// `UUID` is deliberately absent: Swift writes it uppercase and Kotlin lowercase, but
    /// both parse either, so forcing a coder onto every model holding an identifier would
    /// cost more than the textual difference does.
    public var needsGeneratedCoder: Bool {
        switch self {
        case .instant, .duration, .date, .decimal: true
        default: false
        }
    }

    /// Whether a literal default can sensibly be written for this type. `UUID`, `URL` and
    /// the temporal types have no literal syntax in the DSL.
    public var supportsLiteralDefault: Bool {
        switch self {
        case .string, .bool, .int32, .int64, .float, .double, .decimal: true
        case .uuid, .url, .date, .instant, .duration: false
        }
    }
}
