import Foundation

/// Validates a written default against the field's resolved type.
enum DefaultValueChecker {

    /// - Returns: the checked value, or `nil` when it does not fit the type. A diagnostic
    ///   is reported in that case and the field simply carries no default.
    static func check(_ literal: LiteralSyntax,
                      against type: TypeRef,
                      fieldName: String,
                      resolveAlias: (String) -> TypeRef?,
                      lookupEnum: (String) -> EnumSyntax?,
                      diagnostics: inout DiagnosticBag) -> DefaultValue? {

        // `null` is the one literal that cares about the optional wrapper itself.
        if case .null(let range) = literal {
            guard type.isOptional else {
                diagnostics.error(.invalidDefaultValue,
                                  "'\(fieldName)' is not optional, so it cannot default to null",
                                  at: range,
                                  notes: [.init(message: "write '\(type.described)?' to allow a null value")])
                return nil
            }
            return .null
        }

        let underlying = resolved(type.unwrapped, resolveAlias: resolveAlias)

        switch literal {
        case .null:
            return nil   // handled above

        case .string(let value, let range):
            guard underlying.scalar == .string else {
                return reject(literal, range: range, fieldName: fieldName,
                              type: type, diagnostics: &diagnostics)
            }
            return .string(value)

        case .boolean(let value, let range):
            guard underlying.scalar == .bool else {
                return reject(literal, range: range, fieldName: fieldName,
                              type: type, diagnostics: &diagnostics)
            }
            return .boolean(value)

        case .integer(let lexeme, let range):
            guard let scalar = underlying.scalar, scalar.isNumeric else {
                return reject(literal, range: range, fieldName: fieldName,
                              type: type, diagnostics: &diagnostics)
            }
            if scalar.isIntegral, !fits(lexeme: lexeme, in: scalar) {
                diagnostics.error(.invalidDefaultValue,
                                  "\(lexeme) does not fit in \(scalar.rawValue)",
                                  at: range,
                                  notes: [.init(message: "use Int64 for values outside the range of Int32")])
                return nil
            }
            // An integer literal is a perfectly natural way to write a floating-point
            // default, so `ratio: Double = 0` is accepted and emitted as a float.
            return scalar.isFloatingPoint ? .float(lexeme: lexeme) : .integer(lexeme: lexeme)

        case .float(let lexeme, let range):
            guard let scalar = underlying.scalar, scalar.isFloatingPoint else {
                return reject(literal, range: range, fieldName: fieldName,
                              type: type, diagnostics: &diagnostics)
            }
            return .float(lexeme: lexeme)

        case .emptyList(let range):
            switch underlying {
            case .list: return .emptyList
            case .set: return .emptySet
            default:
                return reject(literal, range: range, fieldName: fieldName,
                              type: type, diagnostics: &diagnostics)
            }

        case .emptyMap(let range):
            guard case .map = underlying else {
                return reject(literal, range: range, fieldName: fieldName,
                              type: type, diagnostics: &diagnostics)
            }
            return .emptyMap

        case .enumCase(let name, let range):
            guard case .named(let typeName, .enum) = underlying else {
                return reject(literal, range: range, fieldName: fieldName,
                              type: type, diagnostics: &diagnostics)
            }
            guard let declaration = lookupEnum(typeName) else { return nil }
            let caseNames = declaration.cases.map(\.name.text)
            guard caseNames.contains(name.text) else {
                var notes: [Diagnostic.Note] = []
                if let suggestion = NameSuggestion.closest(to: name.text, among: caseNames) {
                    notes.append(.init(message: "did you mean '.\(suggestion)'?"))
                }
                diagnostics.error(.unknownEnumCase,
                                  "'\(typeName)' has no case '\(name.text)'",
                                  at: range,
                                  notes: notes)
                return nil
            }
            return .enumCase(name.text)
        }
    }

    /// Follow type aliases to whatever they ultimately name, so `typealias UserID = UUID`
    /// behaves like `UUID` when checking a default.
    private static func resolved(_ type: TypeRef, resolveAlias: (String) -> TypeRef?) -> TypeRef {
        var current = type
        var hops = 0
        while case .named(let name, .alias) = current, hops < 32 {
            guard let target = resolveAlias(name) else { return current }
            current = target.unwrapped
            hops += 1
        }
        return current
    }

    private static func reject(_ literal: LiteralSyntax,
                               range: SourceRange,
                               fieldName: String,
                               type: TypeRef,
                               diagnostics: inout DiagnosticBag) -> DefaultValue? {
        var notes: [Diagnostic.Note] = []
        if let scalar = type.unwrapped.scalar, !scalar.supportsLiteralDefault {
            notes.append(.init(message: "\(scalar.rawValue) has no literal form in this language"))
        }
        diagnostics.error(.invalidDefaultValue,
                          "cannot use \(literal.describedForDiagnostic) as a default for '\(fieldName)', which is \(type.described)",
                          at: range,
                          notes: notes)
        return nil
    }

    private static func fits(lexeme: String, in scalar: ScalarType) -> Bool {
        let digits = lexeme.replacingOccurrences(of: "_", with: "")
        guard let value = Int64(digits) else { return false }
        switch scalar {
        case .int32: return value >= Int64(Int32.min) && value <= Int64(Int32.max)
        case .int64: return true
        default: return true
        }
    }
}
