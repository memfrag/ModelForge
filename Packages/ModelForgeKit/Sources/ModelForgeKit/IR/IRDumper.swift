import Foundation

/// Renders the resolved module as an indented outline.
///
/// Used by the IR tests to prove that different spellings of the same thing normalize
/// identically, and by the Engineering Mode dump view. Source ranges are deliberately
/// omitted: the IR is about meaning, and including positions would make the fixtures
/// churn whenever unrelated text moved.
public enum IRDumper {

    public static func dump(_ module: Module) -> String {
        var lines = ["module"]
        for type in module.types {
            lines += dump(type, level: 1)
        }
        return lines.joined(separator: "\n")
    }

    private static func dump(_ type: TypeDefinition, level: Int) -> [String] {
        switch type {
        case .model(let model):
            var lines = [indent(level) + "model \(model.name)"]
            lines += documentation(model.documentation, model.deprecation, level: level + 1)
            for field in model.fields {
                var text = "field \(field.name): \(field.type.described)"
                if let value = field.defaultValue { text += " = \(value.described)" }
                if let wire = field.serializedName { text += " json=\"\(wire)\"" }
                if field.isTransient { text += " transient" }
                lines.append(indent(level + 1) + text)
                lines += documentation(field.documentation, field.deprecation, level: level + 2)
            }
            return lines

        case .enum(let definition):
            var lines = [indent(level) + "enum \(definition.name)"]
            lines += documentation(definition.documentation, definition.deprecation, level: level + 1)
            for enumCase in definition.cases {
                var text = "case \(enumCase.name)"
                if let wire = enumCase.serializedName { text += " json=\"\(wire)\"" }
                lines.append(indent(level + 1) + text)
                lines += documentation(enumCase.documentation, enumCase.deprecation, level: level + 2)
            }
            return lines

        case .union(let definition):
            var header = "union \(definition.name) discriminator=\"\(definition.discriminator)\""
            if definition.isRecursive { header += " recursive" }
            var lines = [indent(level) + header]
            lines += documentation(definition.documentation, definition.deprecation, level: level + 1)
            for unionCase in definition.cases {
                var text = "case \(unionCase.name)(\(unionCase.payload.described))"
                if let wire = unionCase.serializedName { text += " json=\"\(wire)\"" }
                lines.append(indent(level + 1) + text)
                lines += documentation(unionCase.documentation, unionCase.deprecation, level: level + 2)
            }
            return lines

        case .alias(let definition):
            var lines = [indent(level) + "alias \(definition.name) = \(definition.target.described)"]
            lines += documentation(definition.documentation, definition.deprecation, level: level + 1)
            return lines
        }
    }

    private static func documentation(_ documentation: [String],
                                      _ deprecation: Deprecation?,
                                      level: Int) -> [String] {
        var lines = documentation.map { indent(level) + "doc \"\($0)\"" }
        if let deprecation {
            let message = deprecation.message.map { " \"\($0)\"" } ?? ""
            lines.append(indent(level) + "deprecated\(message)")
        }
        return lines
    }

    private static func indent(_ level: Int) -> String {
        String(repeating: "  ", count: level)
    }
}
