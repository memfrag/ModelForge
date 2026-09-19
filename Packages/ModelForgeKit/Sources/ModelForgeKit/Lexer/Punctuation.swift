import Foundation

public enum Punctuation: String, Sendable, Hashable, CaseIterable {
    case leftBrace = "{"
    case rightBrace = "}"
    case leftParen = "("
    case rightParen = ")"
    case leftBracket = "["
    case rightBracket = "]"
    case leftAngle = "<"
    case rightAngle = ">"
    case colon = ":"
    case comma = ","
    case equals = "="
    case question = "?"
    case at = "@"
    case dot = "."

    init?(scalar: UInt16) {
        switch scalar {
        case 0x7B: self = .leftBrace
        case 0x7D: self = .rightBrace
        case 0x28: self = .leftParen
        case 0x29: self = .rightParen
        case 0x5B: self = .leftBracket
        case 0x5D: self = .rightBracket
        case 0x3C: self = .leftAngle
        case 0x3E: self = .rightAngle
        case 0x3A: self = .colon
        case 0x2C: self = .comma
        case 0x3D: self = .equals
        case 0x3F: self = .question
        case 0x40: self = .at
        case 0x2E: self = .dot
        default: return nil
        }
    }
}
