import Foundation

/// Generates Kotlin data classes, enums and sealed interfaces.
///
/// Unions rely on kotlinx.serialization's own polymorphic encoding rather than anything
/// hand-written: a union becomes a `sealed interface`, and each payload model *implements*
/// it, which is what produces the flat, internally tagged JSON that the Swift side's
/// custom `Codable` matches. That is also why a payload has to be a model — there would be
/// nothing to inline for a scalar.
struct KotlinEmitter: Emitter {

    let configuration: KotlinEmitterConfiguration
    let language = Language.kotlin

    init(configuration: KotlinEmitterConfiguration) {
        self.configuration = configuration
    }

    /// Which sealed interfaces a model belongs to, and under what tag.
    private struct UnionMembership {
        let unionName: String
        let serializedName: String
    }

    func emit(file: SourceFileID, named name: String, from module: Module) -> GeneratedFile {
        let memberships = unionMemberships(in: module)
        let types = module.types(in: file)

        // The body is rendered first so the imports it needs are known before the header
        // is written.
        var body = CodeWriter()
        var requirements = Requirements()

        for type in types {
            body.blank()
            emit(type, into: &body, memberships: memberships, requirements: &requirements)
        }

        var writer = CodeWriter()
        writer.line(ProjectConfiguration.generatedFileHeader)
        writer.blank()

        // File annotations must precede the package declaration.
        let optIns = requirements.optIns.sorted()
        if !optIns.isEmpty {
            let classes = optIns.map { "\($0)::class" }.joined(separator: ", ")
            writer.line("@file:OptIn(\(classes))")
        }
        let serializers = requirements.useSerializers.sorted()
        if !serializers.isEmpty {
            let classes = serializers.map { "\($0)::class" }.joined(separator: ", ")
            writer.line("@file:UseSerializers(\(classes))")
            requirements.imports.insert("kotlinx.serialization.UseSerializers")
        }
        if !optIns.isEmpty || !serializers.isEmpty {
            writer.blank()
        }

        writer.line("package \(configuration.package)")

        let imports = requirements.imports.sorted()
        if !imports.isEmpty {
            writer.blank()
            for name in imports {
                writer.line("import \(name)")
            }
        }

        let header = writer.text
        let declarations = body.text.trimmingCharacters(in: .newlines)
        let contents = declarations.isEmpty ? header : header + "\n" + declarations + "\n"

        return GeneratedFile(name: fileName(forSourceNamed: name),
                             contents: contents,
                             language: .kotlin,
                             sourceFile: file)
    }

    /// What the file needs declared at the top.
    private struct Requirements {
        var imports: Set<String> = []
        var optIns: Set<String> = []
        /// Serializers from the generated support file, applied file-wide.
        var useSerializers: Set<String> = []

        mutating func need(_ mapping: KotlinTypeMapping) {
            if mapping.needsImport { imports.insert(mapping.name) }
            if let optIn = mapping.optIn { optIns.insert(optIn) }
        }

        /// A scalar whose wire representation comes from the support file.
        ///
        /// `@file:UseSerializers` applies to every property of that type in the file,
        /// including ones nested in lists and maps, so no per-property annotation is
        /// needed anywhere.
        mutating func needSerializer(for scalar: ScalarType) {
            switch scalar {
            case .instant: useSerializers.insert(SupportFile.Name.instantSerializer)
            case .duration: useSerializers.insert(SupportFile.Name.durationSerializer)
            case .decimal: useSerializers.insert(SupportFile.Name.decimalSerializer)
            default: break
            }
        }
    }

    private func unionMemberships(in module: Module) -> [String: [UnionMembership]] {
        var result: [String: [UnionMembership]] = [:]
        for type in module.types {
            guard case .union(let union) = type else { continue }
            for unionCase in union.cases {
                guard case .named(let payload, .model) = unionCase.payload else { continue }
                result[payload, default: []].append(
                    UnionMembership(unionName: union.name, serializedName: unionCase.wireName))
            }
        }
        return result
    }

    private func emit(_ type: TypeDefinition,
                      into writer: inout CodeWriter,
                      memberships: [String: [UnionMembership]],
                      requirements: inout Requirements) {
        switch type {
        case .model(let model):
            emit(model, into: &writer, memberships: memberships[model.name] ?? [],
                 requirements: &requirements)
        case .enum(let definition):
            emit(definition, into: &writer, requirements: &requirements)
        case .union(let union):
            emit(union, into: &writer, requirements: &requirements)
        case .alias(let alias):
            emit(alias, into: &writer, requirements: &requirements)
        }
    }

    // MARK: Model

    private func emit(_ model: ModelDefinition,
                      into writer: inout CodeWriter,
                      memberships: [UnionMembership],
                      requirements: inout Requirements) {
        requirements.imports.insert("kotlinx.serialization.Serializable")

        kdoc(model.documentation, into: &writer)
        deprecation(model.deprecation, into: &writer)
        writer.line("@Serializable")

        // A model that appears in a union carries the discriminator value that identifies
        // it. All unions containing it must agree on that value, which semantic analysis
        // checks.
        if let membership = memberships.first {
            requirements.imports.insert("kotlinx.serialization.SerialName")
            writer.line("@SerialName(\"\(escape(membership.serializedName))\")")
        }

        let interfaces = memberships.map(\.unionName).sorted()
        let suffix = interfaces.isEmpty ? "" : " : \(interfaces.joined(separator: ", "))"

        guard !model.fields.isEmpty else {
            // A data class must have at least one parameter; an empty model becomes an
            // object, which is also what kotlinx expects for a payload with no fields.
            writer.line("object \(model.name)\(suffix)")
            return
        }

        writer.line("data class \(model.name)(")
        writer.indented { writer in
            for field in model.fields {
                kdoc(field.documentation, into: &writer)
                deprecation(field.deprecation, into: &writer)
                if field.isTransient {
                    requirements.imports.insert("kotlinx.serialization.Transient")
                    writer.line("@Transient")
                } else if let serialized = field.serializedName {
                    requirements.imports.insert("kotlinx.serialization.SerialName")
                    writer.line("@SerialName(\"\(escape(serialized))\")")
                }
                // kotlinx omits a property equal to its default. Swift has no such rule,
                // so the default is forced onto the wire to keep both platforms producing
                // the same payload for the same value.
                if field.defaultValue != nil, !field.isTransient {
                    requirements.imports.insert("kotlinx.serialization.EncodeDefault")
                    requirements.optIns.insert("kotlinx.serialization.ExperimentalSerializationApi")
                    writer.line("@EncodeDefault")
                }
                let type = render(field.type, requirements: &requirements)
                var line = "val \(escaped(field.name)): \(type)"
                if let value = field.defaultValue {
                    line += " = \(render(value, for: field.type, requirements: &requirements))"
                }
                writer.line("\(line),")
            }
        }
        writer.line(")\(suffix)")
    }

    // MARK: Enum

    private func emit(_ definition: EnumDefinition,
                      into writer: inout CodeWriter,
                      requirements: inout Requirements) {
        requirements.imports.insert("kotlinx.serialization.Serializable")

        kdoc(definition.documentation, into: &writer)
        deprecation(definition.deprecation, into: &writer)
        writer.line("@Serializable")

        guard !definition.cases.isEmpty else {
            writer.line("enum class \(definition.name)")
            return
        }

        writer.line("enum class \(definition.name) {")
        writer.indented { writer in
            for enumCase in definition.cases {
                kdoc(enumCase.documentation, into: &writer)
                deprecation(enumCase.deprecation, into: &writer)
                // The constant is SCREAMING_SNAKE by Kotlin convention while the wire value
                // stays the DSL spelling, so @SerialName is always needed.
                requirements.imports.insert("kotlinx.serialization.SerialName")
                writer.line("@SerialName(\"\(escape(enumCase.wireName))\")")
                writer.line("\(constantName(enumCase.name)),")
            }
        }
        writer.line("}")
    }

    // MARK: Union

    private func emit(_ union: UnionDefinition,
                      into writer: inout CodeWriter,
                      requirements: inout Requirements) {
        requirements.imports.insert("kotlinx.serialization.Serializable")

        kdoc(union.documentation, into: &writer)
        deprecation(union.deprecation, into: &writer)
        writer.line("@Serializable")

        if union.discriminator != UnionDefinition.defaultDiscriminator {
            requirements.imports.insert("kotlinx.serialization.json.JsonClassDiscriminator")
            requirements.optIns.insert("kotlinx.serialization.ExperimentalSerializationApi")
            writer.line("@JsonClassDiscriminator(\"\(escape(union.discriminator))\")")
        }

        // The implementations are the payload models themselves, emitted wherever they are
        // declared — which is what makes the JSON flat.
        writer.line("sealed interface \(union.name)")
    }

    // MARK: Alias

    private func emit(_ alias: AliasDefinition,
                      into writer: inout CodeWriter,
                      requirements: inout Requirements) {
        kdoc(alias.documentation, into: &writer)
        deprecation(alias.deprecation, into: &writer)
        writer.line("typealias \(alias.name) = \(render(alias.target, requirements: &requirements))")
    }

    // MARK: Rendering

    private func render(_ type: TypeRef, requirements: inout Requirements) -> String {
        switch type {
        case .scalar(let scalar):
            let mapping = configuration.mapping(for: scalar)
            requirements.need(mapping)
            requirements.needSerializer(for: scalar)
            return mapping.simpleName
        case .named(let name, _):
            return name
        case .unresolved(let name):
            return name
        case .optional(let wrapped):
            return "\(render(wrapped, requirements: &requirements))?"
        case .list(let element):
            return "List<\(render(element, requirements: &requirements))>"
        case .set(let element):
            return "Set<\(render(element, requirements: &requirements))>"
        case .map(let key, let value):
            return "Map<\(render(key, requirements: &requirements)), \(render(value, requirements: &requirements))>"
        }
    }

    /// Kotlin is far stricter than Swift about numeric literals: an `Int` literal will not
    /// implicitly become a `Double` or a `Float`, and `BigDecimal` has no literal at all.
    private func render(_ value: DefaultValue,
                        for type: TypeRef,
                        requirements: inout Requirements) -> String {
        let scalar = type.unwrapped.scalar

        switch value {
        case .string(let text):
            return "\"\(escape(text))\""
        case .boolean(let flag):
            return flag ? "true" : "false"
        case .null:
            return "null"
        case .emptyList:
            return "emptyList()"
        case .emptySet:
            return "emptySet()"
        case .emptyMap:
            return "emptyMap()"
        case .enumCase(let name):
            if case .named(let typeName, .enum) = type.unwrapped {
                return "\(typeName).\(constantName(name))"
            }
            return constantName(name)
        case .integer(let lexeme), .float(let lexeme):
            return numericLiteral(lexeme, scalar: scalar, requirements: &requirements)
        }
    }

    private func numericLiteral(_ lexeme: String,
                                scalar: ScalarType?,
                                requirements: inout Requirements) -> String {
        switch scalar {
        case .decimal:
            let mapping = configuration.mapping(for: .decimal)
            requirements.need(mapping)
            return "\(mapping.simpleName)(\"\(lexeme)\")"
        case .float:
            return "\(withFractionalPart(lexeme))f"
        case .double:
            return withFractionalPart(lexeme)
        default:
            return lexeme
        }
    }

    /// `2` → `2.0`, because Kotlin will not widen an integer literal to a floating-point
    /// type the way Swift does.
    private func withFractionalPart(_ lexeme: String) -> String {
        let hasExponentOrPoint = lexeme.contains(".") || lexeme.lowercased().contains("e")
        return hasExponentOrPoint ? lexeme : "\(lexeme).0"
    }

    private func kdoc(_ lines: [String], into writer: inout CodeWriter) {
        guard !lines.isEmpty else { return }
        if lines.count == 1 {
            writer.line("/** \(lines[0]) */")
            return
        }
        writer.line("/**")
        for line in lines {
            writer.line(line.isEmpty ? " *" : " * \(line)")
        }
        writer.line(" */")
    }

    private func deprecation(_ deprecation: Deprecation?, into writer: inout CodeWriter) {
        guard let deprecation else { return }
        // Kotlin's @Deprecated requires a message, so give it something when none was
        // written in the schema.
        writer.line("@Deprecated(\"\(escape(deprecation.message ?? "Deprecated"))\")")
    }

    private func constantName(_ name: String) -> String {
        NamingConventions.screamingSnakeCase(name)
    }

    private func escaped(_ name: String) -> String {
        NamingConventions.escapedForKotlin(name)
    }

    private func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\t", with: "\\t")
    }
}
