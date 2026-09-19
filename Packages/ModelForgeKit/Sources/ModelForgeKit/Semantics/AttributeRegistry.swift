import Foundation

/// Where an attribute may appear.
public enum AttributeTarget: String, Sendable, Hashable, CaseIterable {
    case model
    case `enum`
    case union
    case alias
    case field
    case enumCase = "enum case"
    case unionCase = "union case"
}

/// The attributes extracted from a declaration or member after validation.
public struct ResolvedAttributes: Sendable, Hashable {
    public var serializedName: String?
    public var isTransient = false
    public var deprecation: Deprecation?
    public var discriminator: String?
    /// Set when `@identifiable` is present. The payload is the field to use as the
    /// identity, or `nil` to mean "the field called `id`".
    public var identity: Identity?

    public struct Identity: Sendable, Hashable {
        public var fieldName: String?
    }

    public init() {}
}

/// Validates attributes and turns them into typed values.
///
/// Attributes are parsed structurally and checked here rather than in the grammar, which
/// is what lets the language grow new metadata without touching the parser — and lets an
/// unknown attribute produce a spelling suggestion instead of a syntax error.
public enum AttributeRegistry {

    private struct Specification {
        let name: String
        let targets: Set<AttributeTarget>
        /// `nil` means the attribute takes no arguments.
        let argument: Argument?

        enum Argument {
            case requiredString
            case optionalString
        }
    }

    private static let specifications: [Specification] = [
        .init(name: "json", targets: [.field, .enumCase, .unionCase], argument: .requiredString),
        .init(name: "transient", targets: [.field], argument: nil),
        .init(name: "deprecated",
              targets: [.model, .enum, .union, .alias, .field, .enumCase, .unionCase],
              argument: .optionalString),
        .init(name: "discriminator", targets: [.union], argument: .requiredString),
        .init(name: "serializable", targets: [.model, .enum, .union], argument: nil),
        .init(name: "identifiable", targets: [.model], argument: .optionalString)
    ]

    /// Attributes the proposal sketches for a later version. Recognised only so they get a
    /// clear explanation rather than a bare "unknown attribute".
    private static let deferredAttributes: [String: String] = [
        "presence": "field presence is not supported yet; a field is either nullable ('T?') or required",
        "optional": "field presence is not supported yet; write 'T?' to allow a null value",
        "unknownCase": "unknown-value handling for enums is not supported yet",
        "flatten": "flattened union payloads are not supported yet"
    ]

    public static func resolve(_ attributes: [AttributeSyntax],
                               target: AttributeTarget,
                               ownerDescription: String,
                               diagnostics: inout DiagnosticBag) -> ResolvedAttributes {
        var resolved = ResolvedAttributes()
        var seen: [String: SourceRange] = [:]

        for attribute in attributes {
            let name = attribute.name.text

            if let explanation = deferredAttributes[name] {
                diagnostics.error(.unknownAttribute,
                                  "'@\(name)' is not supported in this version",
                                  at: attribute.range,
                                  notes: [.init(message: explanation)])
                continue
            }

            guard let specification = specifications.first(where: { $0.name == name }) else {
                var notes: [Diagnostic.Note] = []
                if let suggestion = NameSuggestion.closest(to: name,
                                                           among: specifications.map(\.name)) {
                    notes.append(.init(message: "did you mean '@\(suggestion)'?"))
                }
                diagnostics.error(.unknownAttribute,
                                  "unknown attribute '@\(name)'",
                                  at: attribute.range,
                                  notes: notes)
                continue
            }

            guard specification.targets.contains(target) else {
                let allowed = specification.targets
                    .map(\.rawValue).sorted().joined(separator: ", ")
                diagnostics.error(.attributeNotAllowedHere,
                                  "'@\(name)' cannot be used on \(ownerDescription)",
                                  at: attribute.range,
                                  notes: [.init(message: "it is allowed on: \(allowed)")])
                continue
            }

            if let previous = seen[name] {
                diagnostics.error(.redundantAttribute,
                                  "duplicate attribute '@\(name)'",
                                  at: attribute.range,
                                  notes: [.init(message: "it was already given here", range: previous)])
                continue
            }
            seen[name] = attribute.range

            apply(specification, attribute: attribute, into: &resolved, diagnostics: &diagnostics)
        }

        return resolved
    }

    private static func apply(_ specification: Specification,
                              attribute: AttributeSyntax,
                              into resolved: inout ResolvedAttributes,
                              diagnostics: inout DiagnosticBag) {
        let name = specification.name

        switch specification.argument {
        case nil:
            guard attribute.arguments.isEmpty else {
                diagnostics.error(.invalidAttributeArguments,
                                  "'@\(name)' does not take any arguments",
                                  at: attribute.arguments[0].range)
                return
            }

        case .requiredString:
            guard attribute.arguments.count == 1 else {
                diagnostics.error(.invalidAttributeArguments,
                                  "'@\(name)' takes exactly one string argument",
                                  at: attribute.range)
                return
            }

        case .optionalString:
            guard attribute.arguments.count <= 1 else {
                diagnostics.error(.invalidAttributeArguments,
                                  "'@\(name)' takes at most one string argument",
                                  at: attribute.arguments[1].range)
                return
            }
        }

        if let argument = attribute.arguments.first, let label = argument.label {
            diagnostics.error(.invalidAttributeArguments,
                              "'@\(name)' does not take a labelled argument",
                              at: label.range)
            return
        }

        switch name {
        case "json":
            guard let value = stringArgument(attribute, name: name, diagnostics: &diagnostics) else { return }
            guard !value.isEmpty else {
                diagnostics.error(.invalidAttributeArguments,
                                  "'@json' needs a non-empty name",
                                  at: attribute.arguments[0].range)
                return
            }
            resolved.serializedName = value

        case "transient":
            resolved.isTransient = true

        case "deprecated":
            if attribute.arguments.isEmpty {
                resolved.deprecation = Deprecation(message: nil)
            } else if let value = stringArgument(attribute, name: name, diagnostics: &diagnostics) {
                resolved.deprecation = Deprecation(message: value)
            }

        case "discriminator":
            guard let value = stringArgument(attribute, name: name, diagnostics: &diagnostics) else { return }
            guard !value.isEmpty else {
                diagnostics.error(.invalidAttributeArguments,
                                  "'@discriminator' needs a non-empty key",
                                  at: attribute.arguments[0].range)
                return
            }
            resolved.discriminator = value

        case "identifiable":
            if attribute.arguments.isEmpty {
                resolved.identity = ResolvedAttributes.Identity(fieldName: nil)
            } else if let value = stringArgument(attribute, name: name, diagnostics: &diagnostics) {
                guard !value.isEmpty else {
                    diagnostics.error(.invalidAttributeArguments,
                                      "'@identifiable' needs a field name",
                                      at: attribute.arguments[0].range)
                    return
                }
                resolved.identity = ResolvedAttributes.Identity(fieldName: value)
            }

        case "serializable":
            // Everything is serializable already. Saying so is harmless but pointless.
            diagnostics.warning(.redundantAttribute,
                                "'@serializable' has no effect",
                                at: attribute.range,
                                notes: [.init(message: "all generated types are serializable by default")])

        default:
            break
        }
    }

    private static func stringArgument(_ attribute: AttributeSyntax,
                                       name: String,
                                       diagnostics: inout DiagnosticBag) -> String? {
        guard let argument = attribute.arguments.first else { return nil }
        guard case .string(let value, _) = argument.value else {
            diagnostics.error(.invalidAttributeArguments,
                              "'@\(name)' takes a string, but found \(argument.value.describedForDiagnostic)",
                              at: argument.range)
            return nil
        }
        return value
    }
}
