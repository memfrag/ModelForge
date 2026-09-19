import Foundation

/// Generates Swift value types.
///
/// Two choices worth knowing about:
///
/// - **Every stored property is a `let`.** Defaults are expressed in the generated
///   initialisers rather than as property initialisers, which keeps the types immutable
///   and reads the way a Swift developer would write it by hand.
/// - **A default means the key may be absent.** Synthesized `Codable` throws when a key is
///   missing even if the property has a value, while Kotlin's serialization does not — so
///   a model with defaults gets a hand-written `init(from:)` using `decodeIfPresent`, and
///   the two platforms agree.
struct SwiftEmitter: Emitter {

    let configuration: SwiftEmitterConfiguration
    let language = Language.swift

    init(configuration: SwiftEmitterConfiguration) {
        self.configuration = configuration
    }

    func emit(file: SourceFileID, named name: String, from module: Module) -> GeneratedFile {
        var writer = CodeWriter()
        writer.line(ProjectConfiguration.generatedFileHeader)
        if let module = configuration.module {
            writer.line("// Module: \(module)")
        }
        writer.blank()
        writer.line("import Foundation")

        for type in module.types(in: file) {
            writer.blank()
            emit(type, into: &writer, module: module)
        }

        return GeneratedFile(name: fileName(forSourceNamed: name),
                             contents: writer.text,
                             language: .swift,
                             sourceFile: file)
    }

    private func emit(_ type: TypeDefinition, into writer: inout CodeWriter, module: Module) {
        switch type {
        case .model(let model): emit(model, into: &writer)
        case .enum(let definition): emit(definition, into: &writer)
        case .union(let union): emit(union, into: &writer)
        case .alias(let alias): emit(alias, into: &writer)
        }
    }

    // MARK: Conformances

    private func modelConformances(for model: ModelDefinition) -> [String] {
        var conformances: [String] = []
        // Identifiable first: it says what the type *is*, where the others say how it is
        // handled.
        if model.identityField != nil { conformances.append("Identifiable") }
        if configuration.codable { conformances.append("Codable") }
        if configuration.hashable {
            conformances.append("Hashable")
        } else if configuration.equatable {
            conformances.append("Equatable")
        }
        if configuration.sendable { conformances.append("Sendable") }
        return conformances
    }

    /// Unions cannot be `Identifiable`, so they take the plain set.
    private var unionConformances: [String] {
        var conformances: [String] = []
        if configuration.codable { conformances.append("Codable") }
        if configuration.hashable {
            conformances.append("Hashable")
        } else if configuration.equatable {
            conformances.append("Equatable")
        }
        if configuration.sendable { conformances.append("Sendable") }
        return conformances
    }

    private func inherits(_ conformances: [String]) -> String {
        conformances.isEmpty ? "" : ": " + conformances.joined(separator: ", ")
    }

    // MARK: Model

    private func emit(_ model: ModelDefinition, into writer: inout CodeWriter) {
        documentation(model.documentation, into: &writer)
        availability(model.deprecation, into: &writer)

        let access = configuration.accessLevel.prefix
        writer.block("\(access)struct \(model.name)\(inherits(modelConformances(for: model)))") { writer in
            for field in model.fields {
                documentation(field.documentation, into: &writer)
                availability(field.deprecation, into: &writer)
                writer.line("\(access)let \(escaped(field.name)): \(render(field.type))")
            }

            // Synthesized Codable disagrees with this language about optionals in both
            // directions: `init(from:)` lets an absent key become nil, and `encode(to:)`
            // drops a nil instead of writing null. This language says a key is required
            // unless the field has a default, and kotlinx writes the null — so a model
            // with any optional gets both members written by hand.
            let hasOptional = model.fields.contains { $0.isSerialized && $0.type.isOptional }
            // A field whose wire representation differs from its natural type has to be
            // converted explicitly in both directions.
            let hasWireConversion = model.fields.contains {
                $0.isSerialized && wireType(for: $0.type) != nil
            }
            let needsDecoder = configuration.codable && (model.hasDefaults || hasOptional || hasWireConversion)
            let needsEncoder = configuration.codable && (hasOptional || hasWireConversion)
            let needsKeys = model.needsCodingKeys || needsDecoder || needsEncoder

            // A model identified by a field that is not called `id` needs a property to
            // satisfy `Identifiable`.
            if let identity = model.identityField, !model.identityIsNamedID,
               let field = model.fields.first(where: { $0.name == identity }) {
                writer.blank()
                writer.line("\(access)var id: \(render(field.type)) { \(escaped(field.name)) }")
            }

            if needsKeys {
                writer.blank()
                emitCodingKeys(for: model, into: &writer)
            }

            if !model.fields.isEmpty, needsDecoder || configuration.accessLevel == .public {
                writer.blank()
                emitMemberwiseInitializer(for: model, into: &writer)
            }

            if needsDecoder {
                writer.blank()
                emitDecoder(for: model, into: &writer)
            }

            if needsEncoder {
                writer.blank()
                emitEncoder(for: model, into: &writer)
            }
        }
    }

    private func emitCodingKeys(for model: ModelDefinition, into writer: inout CodeWriter) {
        writer.block("private enum CodingKeys: String, CodingKey") { writer in
            for field in model.fields where field.isSerialized {
                if let serialized = field.serializedName {
                    writer.line("case \(escaped(field.name)) = \"\(escape(serialized))\"")
                } else {
                    writer.line("case \(escaped(field.name))")
                }
            }
        }
    }

    private func emitMemberwiseInitializer(for model: ModelDefinition, into writer: inout CodeWriter) {
        let access = configuration.accessLevel.prefix
        let parameters = model.fields.map { field -> String in
            let base = "\(escaped(field.name)): \(render(field.type))"
            guard let value = field.defaultValue else { return base }
            return "\(base) = \(render(value, for: field.type))"
        }

        // One parameter per line once the signature would get long, which is what keeps a
        // wide model readable in the preview pane.
        let singleLine = "\(access)init(\(parameters.joined(separator: ", ")))"
        if singleLine.count <= 100 {
            writer.block(singleLine) { writer in
                for field in model.fields {
                    writer.line("self.\(escaped(field.name)) = \(escaped(field.name))")
                }
            }
            return
        }

        writer.line("\(access)init(")
        writer.indented { writer in
            for (index, parameter) in parameters.enumerated() {
                writer.line(index == parameters.count - 1 ? parameter : "\(parameter),")
            }
        }
        writer.block(")") { writer in
            for field in model.fields {
                writer.line("self.\(escaped(field.name)) = \(escaped(field.name))")
            }
        }
    }

    /// A decoder that treats a default as "this key may be absent".
    private func emitDecoder(for model: ModelDefinition, into writer: inout CodeWriter) {
        let access = configuration.accessLevel.prefix
        writer.block("\(access)init(from decoder: any Decoder) throws") { writer in
            writer.line("let container = try decoder.container(keyedBy: CodingKeys.self)")
            for field in model.fields {
                let name = escaped(field.name)
                guard field.isSerialized else {
                    // Never on the wire: it just takes its default.
                    writer.line("self.\(name) = \(render(field.defaultValue ?? .null, for: field.type))")
                    continue
                }
                guard let value = field.defaultValue else {
                    // No default means the key must be present, even when the value may be
                    // null — which is exactly how kotlinx treats a nullable property with
                    // no default, so the two platforms agree.
                    if let wire = wireType(for: field.type) {
                        let parenthesised = field.type.isOptional ? "(\(wire)).self" : "\(wire).self"
                        writer.line("let \(name) = try container.decode(\(parenthesised), forKey: .\(name))")
                        writer.line("self.\(name) = \(fromWire(name, field.type))")
                    } else {
                        writer.line("self.\(name) = try container.decode(\(decodeType(field.type)), forKey: .\(name))")
                    }
                    continue
                }
                let bare = wireType(for: field.type.unwrapped) ?? bareType(field.type)
                let decoded = "try container.decodeIfPresent(\(bare).self, forKey: .\(name))"
                let converted = wireType(for: field.type) == nil
                    ? decoded
                    : fromWire("(\(decoded))", .optional(field.type.unwrapped))
                if case .null = value {
                    // An optional defaulting to null: absent and null mean the same thing.
                    writer.line("self.\(name) = \(converted)")
                } else {
                    writer.line("self.\(name) = \(converted) ?? \(render(value, for: field.type))")
                }
            }
        }
    }

    /// Writes every serialized field, including nil optionals, so the payload matches
    /// what the Kotlin side produces for the same value.
    private func emitEncoder(for model: ModelDefinition, into writer: inout CodeWriter) {
        let access = configuration.accessLevel.prefix
        writer.block("\(access)func encode(to encoder: any Encoder) throws") { writer in
            writer.line("var container = encoder.container(keyedBy: CodingKeys.self)")
            for field in model.fields where field.isSerialized {
                let name = escaped(field.name)
                let value = wireType(for: field.type) == nil
                    ? "self.\(name)"
                    : toWire("self.\(name)", field.type)
                writer.line("try container.encode(\(value), forKey: .\(name))")
            }
        }
    }

    // MARK: Enum

    private func emit(_ definition: EnumDefinition, into writer: inout CodeWriter) {
        guard !definition.isExtensible else {
            emitExtensible(definition, into: &writer)
            return
        }

        documentation(definition.documentation, into: &writer)
        availability(definition.deprecation, into: &writer)

        // A String-backed enum is Equatable and Hashable already, so listing those would
        // be noise.
        var conformances = ["String"]
        if configuration.codable { conformances.append("Codable") }
        if configuration.sendable { conformances.append("Sendable") }

        let access = configuration.accessLevel.prefix
        writer.block("\(access)enum \(definition.name): \(conformances.joined(separator: ", "))") { writer in
            for enumCase in definition.cases {
                documentation(enumCase.documentation, into: &writer)
                availability(enumCase.deprecation, into: &writer)
                if let serialized = enumCase.serializedName {
                    writer.line("case \(escaped(enumCase.name)) = \"\(escape(serialized))\"")
                } else {
                    writer.line("case \(escaped(enumCase.name))")
                }
            }
        }
    }

    /// An enum that accepts values it does not know.
    ///
    /// A `RawRepresentable` struct rather than an `enum`, because an enum cannot hold a
    /// case it was not compiled with. This is the shape Foundation itself uses for
    /// open-ended string constants, and it round-trips an unfamiliar value untouched
    /// instead of failing the whole payload.
    private func emitExtensible(_ definition: EnumDefinition, into writer: inout CodeWriter) {
        documentation(definition.documentation, into: &writer)
        availability(definition.deprecation, into: &writer)

        var conformances = ["RawRepresentable"]
        if configuration.codable { conformances.append("Codable") }
        conformances.append("Hashable")
        if configuration.sendable { conformances.append("Sendable") }

        let access = configuration.accessLevel.prefix
        writer.block("\(access)struct \(definition.name): \(conformances.joined(separator: ", "))") { writer in
            writer.line("\(access)let rawValue: String")
            writer.blank()
            writer.line("\(access)init(rawValue: String) {")
            writer.indented { $0.line("self.rawValue = rawValue") }
            writer.line("}")

            if !definition.cases.isEmpty {
                writer.blank()
                for enumCase in definition.cases {
                    documentation(enumCase.documentation, into: &writer)
                    availability(enumCase.deprecation, into: &writer)
                    writer.line("\(access)static let \(escaped(enumCase.name)) = \(definition.name)(rawValue: \"\(escape(enumCase.wireName))\")")
                }
            }

            guard configuration.codable else { return }

            writer.blank()
            writer.block("\(access)init(from decoder: any Decoder) throws") { writer in
                writer.line("self.rawValue = try decoder.singleValueContainer().decode(String.self)")
            }

            writer.blank()
            writer.block("\(access)func encode(to encoder: any Encoder) throws") { writer in
                writer.line("var container = encoder.singleValueContainer()")
                writer.line("try container.encode(self.rawValue)")
            }
        }
    }

    // MARK: Union

    /// Unions are internally tagged: the discriminator sits alongside the payload's own
    /// fields, which is what kotlinx.serialization produces natively on the other side.
    private func emit(_ union: UnionDefinition, into writer: inout CodeWriter) {
        documentation(union.documentation, into: &writer)
        availability(union.deprecation, into: &writer)

        let access = configuration.accessLevel.prefix
        let keyword = union.isRecursive ? "indirect enum" : "enum"
        writer.block("\(access)\(keyword) \(union.name)\(inherits(unionConformances))") { writer in
            for unionCase in union.cases {
                documentation(unionCase.documentation, into: &writer)
                availability(unionCase.deprecation, into: &writer)
                writer.line("case \(escaped(unionCase.name))(\(render(unionCase.payload)))")
            }

            guard configuration.codable, !union.cases.isEmpty else { return }

            writer.blank()
            writer.block("private enum CodingKeys: String, CodingKey") { writer in
                writer.line("case discriminator = \"\(escape(union.discriminator))\"")
            }

            writer.blank()
            writer.block("private enum Discriminator: String, Codable") { writer in
                for unionCase in union.cases {
                    if unionCase.wireName == unionCase.name {
                        writer.line("case \(escaped(unionCase.name))")
                    } else {
                        writer.line("case \(escaped(unionCase.name)) = \"\(escape(unionCase.wireName))\"")
                    }
                }
            }

            writer.blank()
            writer.block("\(access)init(from decoder: any Decoder) throws") { writer in
                writer.line("let container = try decoder.container(keyedBy: CodingKeys.self)")
                writer.line("switch try container.decode(Discriminator.self, forKey: .discriminator) {")
                for unionCase in union.cases {
                    let name = escaped(unionCase.name)
                    writer.line("case .\(name):")
                    writer.indented { writer in
                        writer.line("self = .\(name)(try \(bareType(unionCase.payload))(from: decoder))")
                    }
                }
                writer.line("}")
            }

            writer.blank()
            writer.block("\(access)func encode(to encoder: any Encoder) throws") { writer in
                writer.line("var container = encoder.container(keyedBy: CodingKeys.self)")
                writer.line("switch self {")
                for unionCase in union.cases {
                    let name = escaped(unionCase.name)
                    writer.line("case .\(name)(let value):")
                    writer.indented { writer in
                        writer.line("try container.encode(Discriminator.\(name), forKey: .discriminator)")
                        writer.line("try value.encode(to: encoder)")
                    }
                }
                writer.line("}")
            }
        }
    }

    // MARK: Alias

    private func emit(_ alias: AliasDefinition, into writer: inout CodeWriter) {
        documentation(alias.documentation, into: &writer)
        availability(alias.deprecation, into: &writer)
        writer.line("\(configuration.accessLevel.prefix)typealias \(alias.name) = \(render(alias.target))")
    }

    // MARK: Rendering

    func render(_ type: TypeRef) -> String {
        switch type {
        case .scalar(let scalar): configuration.type(for: scalar)
        case .named(let name, _): name
        case .unresolved(let name): name
        case .optional(let wrapped): "\(render(wrapped))?"
        case .list(let element): "[\(render(element))]"
        case .set(let element): "Set<\(render(element))>"
        case .map(let key, let value): "[\(render(key)): \(render(value))]"
        }
    }

    /// The type without its outer optional, for `decodeIfPresent` and payload decoding.
    private func bareType(_ type: TypeRef) -> String {
        render(type.unwrapped)
    }

    // MARK: Wire conversions

    /// The type a field is decoded as, when that differs from the type it is stored as.
    ///
    /// Returns `nil` when the natural type already codes correctly — which is the common
    /// case, so most models keep synthesized `Codable`.
    private func wireType(for type: TypeRef) -> String? {
        switch type {
        case .scalar(let scalar):
            switch scalar {
            case .instant: SupportFile.Name.instantCoder
            case .duration: SupportFile.Name.durationCoder
            default: nil
            }
        case .optional(let wrapped):
            wireType(for: wrapped).map { "\($0)?" }
        case .list(let element):
            wireType(for: element).map { "[\($0)]" }
        case .set(let element):
            wireType(for: element).map { "Set<\($0)>" }
        case .map(let key, let value):
            wireType(for: value).map { "[\(render(key)): \($0)]" }
        case .named, .unresolved:
            nil
        }
    }

    /// Convert a decoded wire value into the stored type.
    private func fromWire(_ expression: String, _ type: TypeRef) -> String {
        switch type {
        case .scalar:
            "\(expression).value"
        case .optional(let wrapped):
            wrapped.isScalarNeedingWire ? "\(expression)?.value"
                                        : "\(expression).map { \(fromWire("$0", wrapped)) }"
        case .list(let element):
            "\(expression).map { \(fromWire("$0", element)) }"
        case .set(let element):
            "Set(\(expression).map { \(fromWire("$0", element)) })"
        case .map(_, let value):
            "\(expression).mapValues { \(fromWire("$0", value)) }"
        case .named, .unresolved:
            expression
        }
    }

    /// Convert a stored value into the form written to the wire.
    private func toWire(_ expression: String, _ type: TypeRef) -> String {
        switch type {
        case .scalar(let scalar):
            "\(wrapperName(for: scalar) ?? "")(\(expression))"
        case .optional(let wrapped):
            wrapped.isScalarNeedingWire
                ? "\(expression).map { \(toWire("$0", wrapped)) }"
                : "\(expression).map { \(toWire("$0", wrapped)) }"
        case .list(let element):
            "\(expression).map { \(toWire("$0", element)) }"
        case .set(let element):
            "Set(\(expression).map { \(toWire("$0", element)) })"
        case .map(_, let value):
            "\(expression).mapValues { \(toWire("$0", value)) }"
        case .named, .unresolved:
            expression
        }
    }

    private func wrapperName(for scalar: ScalarType) -> String? {
        switch scalar {
        case .instant: SupportFile.Name.instantCoder
        case .duration: SupportFile.Name.durationCoder
        default: nil
        }
    }

    /// A metatype expression for `decode(_:forKey:)`.
    ///
    /// Optionals are parenthesised so the result is unambiguous for nested types such as
    /// `[String: String]?`.
    private func decodeType(_ type: TypeRef) -> String {
        type.isOptional ? "(\(render(type))).self" : "\(render(type)).self"
    }

    private func render(_ value: DefaultValue, for type: TypeRef) -> String {
        switch value {
        case .string(let text): "\"\(escape(text))\""
        case .boolean(let flag): flag ? "true" : "false"
        case .integer(let lexeme), .float(let lexeme): lexeme
        case .null: "nil"
        case .emptyList, .emptySet: "[]"
        case .emptyMap: "[:]"
        case .enumCase(let name): ".\(escaped(name))"
        }
    }

    private func documentation(_ lines: [String], into writer: inout CodeWriter) {
        for line in lines {
            writer.line(line.isEmpty ? "///" : "/// \(line)")
        }
    }

    private func availability(_ deprecation: Deprecation?, into writer: inout CodeWriter) {
        guard let deprecation else { return }
        if let message = deprecation.message {
            writer.line("@available(*, deprecated, message: \"\(escape(message))\")")
        } else {
            writer.line("@available(*, deprecated)")
        }
    }

    private func escaped(_ name: String) -> String {
        NamingConventions.escapedForSwift(name)
    }

    private func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\t", with: "\\t")
    }
}
