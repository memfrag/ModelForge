import Foundation

/// Renders a syntax tree as an indented, readable outline.
///
/// This backs both the parser snapshot tests and the Engineering Mode dump view. Having
/// it from the first commit is what makes parser work debuggable — Markin's own parser
/// does the same thing with `formatDebugString(level:)`.
///
/// Source ranges are printed as `line:column` rather than offsets so fixtures stay
/// readable and don't churn when text is added earlier in the file.
public enum SyntaxDumper {

    public static func dump(_ document: DocumentSyntax) -> String {
        var output: [String] = ["document"]
        for declaration in document.declarations {
            output += dump(declaration, level: 1)
        }
        return output.joined(separator: "\n")
    }

    // MARK: Declarations

    private static func dump(_ declaration: DeclarationSyntax, level: Int) -> [String] {
        switch declaration {
        case .model(let model):
            var lines = [line(level, "model \(name(model.name))", model.range)]
            lines += trivia(model.documentation, model.attributes, level: level + 1)
            for field in model.fields {
                lines += dump(field, level: level + 1)
            }
            return lines

        case .enum(let declaration):
            var lines = [line(level, "enum \(name(declaration.name))", declaration.range)]
            lines += trivia(declaration.documentation, declaration.attributes, level: level + 1)
            for enumCase in declaration.cases {
                lines.append(line(level + 1, "case \(name(enumCase.name))", enumCase.range))
                lines += trivia(enumCase.documentation, enumCase.attributes, level: level + 2)
            }
            return lines

        case .union(let declaration):
            var lines = [line(level, "union \(name(declaration.name))", declaration.range)]
            lines += trivia(declaration.documentation, declaration.attributes, level: level + 1)
            for unionCase in declaration.cases {
                lines.append(line(level + 1,
                                  "case \(name(unionCase.name))(\(describe(unionCase.payload)))",
                                  unionCase.range))
                lines += trivia(unionCase.documentation, unionCase.attributes, level: level + 2)
            }
            return lines

        case .typeAlias(let declaration):
            var lines = [line(level,
                              "typealias \(name(declaration.name)) = \(describe(declaration.target))",
                              declaration.range)]
            lines += trivia(declaration.documentation, declaration.attributes, level: level + 1)
            return lines
        }
    }

    private static func dump(_ field: FieldSyntax, level: Int) -> [String] {
        var text = "field \(name(field.name)): \(describe(field.type))"
        if let defaultValue = field.defaultValue {
            text += " = \(describe(defaultValue))"
        }
        var lines = [line(level, text, field.range)]
        lines += trivia(field.documentation, field.attributes, level: level + 1)
        return lines
    }

    private static func trivia(_ documentation: [DocCommentSyntax],
                               _ attributes: [AttributeSyntax],
                               level: Int) -> [String] {
        var lines: [String] = []
        for comment in documentation {
            lines.append(indent(level) + "doc \(quote(comment.text))")
        }
        for attribute in attributes {
            let arguments = attribute.arguments.map { argument -> String in
                if let label = argument.label {
                    return "\(label.text): \(describe(argument.value))"
                }
                return describe(argument.value)
            }
            let suffix = arguments.isEmpty ? "" : "(\(arguments.joined(separator: ", ")))"
            lines.append(indent(level) + "attribute @\(attribute.name.text)\(suffix)")
        }
        return lines
    }

    // MARK: Describing

    /// A type rendered back in DSL notation, which is what makes a dump readable.
    public static func describe(_ type: TypeSyntax) -> String {
        switch type {
        case .named(let identifier): name(identifier)
        case .list(let element, _): "[\(describe(element))]"
        case .set(let element, _): "Set<\(describe(element))>"
        case .map(let key, let value, _): "Map<\(describe(key)), \(describe(value))>"
        case .optional(let wrapped, _): "\(describe(wrapped))?"
        case .missing: "<missing>"
        }
    }

    public static func describe(_ literal: LiteralSyntax) -> String {
        switch literal {
        case .string(let value, _): quote(value)
        case .integer(let lexeme, _), .float(let lexeme, _): lexeme
        case .boolean(let value, _): value ? "true" : "false"
        case .null: "null"
        case .emptyList: "[]"
        case .emptyMap: "{}"
        case .enumCase(let identifier, _): ".\(identifier.text)"
        }
    }

    // MARK: Formatting

    private static func name(_ identifier: IdentifierSyntax) -> String {
        identifier.isMissing ? "<missing>" : identifier.text
    }

    private static func line(_ level: Int, _ text: String, _ range: SourceRange) -> String {
        "\(indent(level))\(text)  @\(range.start.line):\(range.start.column)"
    }

    private static func indent(_ level: Int) -> String {
        String(repeating: "  ", count: level)
    }

    private static func quote(_ text: String) -> String {
        "\"\(text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
    }
}
