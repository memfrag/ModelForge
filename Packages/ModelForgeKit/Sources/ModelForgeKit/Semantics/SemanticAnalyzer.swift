import Foundation

/// Resolves a project's parsed files into a single `Module`.
///
/// Semantic analysis and IR lowering are one pass because every check needs resolution and
/// the IR is the natural place to put the resolved result.
///
/// Like the parser, this never stops at the first problem. An unresolved type becomes
/// `TypeRef.unresolved` and flows through to the emitters, which print it verbatim — so
/// while the user types `Str` → `Stri` → `String` the previews keep updating and the
/// diagnostic clears on its own. Generate is what refuses to run while errors exist.
public struct SemanticAnalyzer {

    /// Analyse every file in the project together. There is one flat namespace, so the
    /// order of `documents` affects only the order of the output, never what resolves.
    public static func analyze(_ documents: [DocumentSyntax],
                               diagnostics: inout DiagnosticBag) -> Module {
        var analyzer = SemanticAnalyzer(documents: documents)
        return analyzer.run(diagnostics: &diagnostics)
    }

    private let documents: [DocumentSyntax]
    private var symbols = SymbolTable()
    private var enumsByName: [String: EnumSyntax] = [:]
    private var aliasTargets: [String: TypeRef] = [:]
    private var modelsByName: [String: ModelDefinition] = [:]

    private init(documents: [DocumentSyntax]) {
        self.documents = documents
    }

    private mutating func run(diagnostics: inout DiagnosticBag) -> Module {
        collectSymbols(diagnostics: &diagnostics)

        var types: [TypeDefinition] = []
        for document in documents {
            for declaration in document.declarations {
                guard !declaration.name.isMissing else { continue }
                guard symbols[declaration.name.text]?.declaredAt == declaration.name.range else {
                    // A duplicate: already reported while collecting symbols. Emitting it
                    // too would produce code that does not compile.
                    continue
                }
                if let type = lower(declaration, in: document.file, diagnostics: &diagnostics) {
                    types.append(type)
                }
            }
        }

        types = applyRecursionRules(to: types, diagnostics: &diagnostics)
        checkUnionPayloads(in: types, diagnostics: &diagnostics)
        checkPayloadTagConsistency(in: types, diagnostics: &diagnostics)

        return Module(types: types)
    }

    // MARK: Pass 1 — names

    private mutating func collectSymbols(diagnostics: inout DiagnosticBag) {
        for document in documents {
            for declaration in document.declarations {
                let name = declaration.name
                guard !name.isMissing else { continue }

                if ReservedNames.isForbiddenTypeName(name.text) {
                    diagnostics.error(.builtinRedeclared,
                                      "'\(name.text)' is reserved and cannot be declared",
                                      at: name.range,
                                      notes: [.init(message: "it would collide with a type in the generated code")])
                    continue
                }

                let kind: Symbol.Kind = switch declaration {
                case .model: .model
                case .enum: .enum
                case .union: .union
                case .typeAlias: .alias
                }

                if let existing = symbols.declare(Symbol(name: name.text,
                                                         kind: kind,
                                                         declaredAt: name.range)) {
                    var notes: [Diagnostic.Note] = []
                    if let previous = existing.declaredAt {
                        notes.append(.init(message: "'\(name.text)' is already declared here", range: previous))
                    }
                    diagnostics.error(.duplicateDeclaration,
                                      "duplicate declaration of '\(name.text)'",
                                      at: name.range,
                                      notes: notes)
                    continue
                }

                if case .enum(let declaration) = declaration {
                    enumsByName[name.text] = declaration
                }
            }
        }
    }

    // MARK: Pass 2 — lowering

    private mutating func lower(_ declaration: DeclarationSyntax,
                                in file: SourceFileID,
                                diagnostics: inout DiagnosticBag) -> TypeDefinition? {
        switch declaration {
        case .model(let model):
            lowerModel(model, in: file, diagnostics: &diagnostics).map(TypeDefinition.model)
        case .enum(let declaration):
            .enum(lowerEnum(declaration, in: file, diagnostics: &diagnostics))
        case .union(let declaration):
            .union(lowerUnion(declaration, in: file, diagnostics: &diagnostics))
        case .typeAlias(let declaration):
            lowerAlias(declaration, in: file, diagnostics: &diagnostics).map(TypeDefinition.alias)
        }
    }

    private mutating func lowerModel(_ syntax: ModelSyntax,
                                     in file: SourceFileID,
                                     diagnostics: inout DiagnosticBag) -> ModelDefinition? {
        let attributes = AttributeRegistry.resolve(syntax.attributes, target: .model,
                                                   ownerDescription: "a model",
                                                   diagnostics: &diagnostics)

        var fields: [FieldDefinition] = []
        var seenNames: [String: SourceRange] = [:]
        var seenWireNames: [String: SourceRange] = [:]

        for fieldSyntax in syntax.fields {
            guard !fieldSyntax.name.isMissing else { continue }
            let name = fieldSyntax.name.text

            if let previous = seenNames[name] {
                diagnostics.error(.duplicateField,
                                  "duplicate field '\(name)' in '\(syntax.name.text)'",
                                  at: fieldSyntax.name.range,
                                  notes: [.init(message: "'\(name)' is already declared here", range: previous)])
                continue
            }
            seenNames[name] = fieldSyntax.name.range

            warnIfReserved(name: name, range: fieldSyntax.name.range,
                           what: "field", diagnostics: &diagnostics)

            // A type the parser could not read has already been reported. Dropping the
            // field keeps the previews free of half-written declarations.
            guard !fieldSyntax.type.containsMissing else { continue }
            let type = resolve(fieldSyntax.type, diagnostics: &diagnostics)

            let fieldAttributes = AttributeRegistry.resolve(fieldSyntax.attributes, target: .field,
                                                            ownerDescription: "a field",
                                                            diagnostics: &diagnostics)

            var defaultValue: DefaultValue?
            if let literal = fieldSyntax.defaultValue {
                defaultValue = DefaultValueChecker.check(
                    literal, against: type, fieldName: name,
                    resolveAlias: { [aliasTargets] in aliasTargets[$0] },
                    lookupEnum: { [enumsByName] in enumsByName[$0] },
                    diagnostics: &diagnostics)
            }

            // Both Swift's synthesized Codable and kotlinx's @Transient need a value to
            // fall back on for a field that never appears on the wire.
            if fieldAttributes.isTransient, defaultValue == nil {
                diagnostics.error(.transientRequiresDefault,
                                  "'@transient' field '\(name)' needs a default value",
                                  at: fieldSyntax.name.range,
                                  notes: [.init(message: "a transient field is never decoded, so it must have something to fall back on")])
            }

            let field = FieldDefinition(name: name, type: type, defaultValue: defaultValue,
                                        serializedName: fieldAttributes.serializedName,
                                        isTransient: fieldAttributes.isTransient,
                                        documentation: fieldSyntax.documentation.map(\.text),
                                        deprecation: fieldAttributes.deprecation,
                                        origin: fieldSyntax.name.range)

            if field.isSerialized {
                if let previous = seenWireNames[field.wireName] {
                    diagnostics.error(.duplicateSerializedName,
                                      "two fields both serialize as '\(field.wireName)'",
                                      at: fieldSyntax.name.range,
                                      notes: [.init(message: "the other one is here", range: previous)])
                } else {
                    seenWireNames[field.wireName] = fieldSyntax.name.range
                }
            }

            fields.append(field)
        }

        let definition = ModelDefinition(name: syntax.name.text, fields: fields,
                                         documentation: syntax.documentation.map(\.text),
                                         deprecation: attributes.deprecation,
                                         sourceFile: file, origin: syntax.range)
        modelsByName[definition.name] = definition
        return definition
    }

    private mutating func lowerEnum(_ syntax: EnumSyntax,
                                    in file: SourceFileID,
                                    diagnostics: inout DiagnosticBag) -> EnumDefinition {
        let attributes = AttributeRegistry.resolve(syntax.attributes, target: .enum,
                                                   ownerDescription: "an enum",
                                                   diagnostics: &diagnostics)

        var cases: [EnumCaseDefinition] = []
        var seen: [String: SourceRange] = [:]
        var seenWireNames: [String: SourceRange] = [:]

        for caseSyntax in syntax.cases {
            guard !caseSyntax.name.isMissing else { continue }
            let name = caseSyntax.name.text

            if let previous = seen[name] {
                diagnostics.error(.duplicateEnumCase,
                                  "duplicate case '\(name)' in '\(syntax.name.text)'",
                                  at: caseSyntax.name.range,
                                  notes: [.init(message: "'\(name)' is already declared here", range: previous)])
                continue
            }
            seen[name] = caseSyntax.name.range

            warnIfReserved(name: name, range: caseSyntax.name.range,
                           what: "enum case", diagnostics: &diagnostics)

            let caseAttributes = AttributeRegistry.resolve(caseSyntax.attributes, target: .enumCase,
                                                           ownerDescription: "an enum case",
                                                           diagnostics: &diagnostics)

            let definition = EnumCaseDefinition(name: name,
                                                serializedName: caseAttributes.serializedName,
                                                documentation: caseSyntax.documentation.map(\.text),
                                                deprecation: caseAttributes.deprecation)

            if let previous = seenWireNames[definition.wireName] {
                diagnostics.error(.duplicateSerializedName,
                                  "two cases both serialize as '\(definition.wireName)'",
                                  at: caseSyntax.name.range,
                                  notes: [.init(message: "the other one is here", range: previous)])
            } else {
                seenWireNames[definition.wireName] = caseSyntax.name.range
            }

            cases.append(definition)
        }

        return EnumDefinition(name: syntax.name.text, cases: cases,
                              documentation: syntax.documentation.map(\.text),
                              deprecation: attributes.deprecation,
                              sourceFile: file, origin: syntax.range)
    }

    private mutating func lowerUnion(_ syntax: UnionSyntax,
                                     in file: SourceFileID,
                                     diagnostics: inout DiagnosticBag) -> UnionDefinition {
        let attributes = AttributeRegistry.resolve(syntax.attributes, target: .union,
                                                   ownerDescription: "a union",
                                                   diagnostics: &diagnostics)

        var cases: [UnionCaseDefinition] = []
        var seen: [String: SourceRange] = [:]
        var seenWireNames: [String: SourceRange] = [:]

        for caseSyntax in syntax.cases {
            guard !caseSyntax.name.isMissing else { continue }
            let name = caseSyntax.name.text

            if let previous = seen[name] {
                diagnostics.error(.duplicateUnionCase,
                                  "duplicate case '\(name)' in '\(syntax.name.text)'",
                                  at: caseSyntax.name.range,
                                  notes: [.init(message: "'\(name)' is already declared here", range: previous)])
                continue
            }
            seen[name] = caseSyntax.name.range

            guard !caseSyntax.payload.containsMissing else { continue }
            let payload = resolve(caseSyntax.payload, diagnostics: &diagnostics)

            let caseAttributes = AttributeRegistry.resolve(caseSyntax.attributes, target: .unionCase,
                                                           ownerDescription: "a union case",
                                                           diagnostics: &diagnostics)

            let definition = UnionCaseDefinition(name: name, payload: payload,
                                                 serializedName: caseAttributes.serializedName,
                                                 documentation: caseSyntax.documentation.map(\.text),
                                                 deprecation: caseAttributes.deprecation,
                                                 payloadOrigin: caseSyntax.payload.range)

            if let previous = seenWireNames[definition.wireName] {
                diagnostics.error(.duplicateSerializedName,
                                  "two cases both serialize as '\(definition.wireName)'",
                                  at: caseSyntax.name.range,
                                  notes: [.init(message: "the other one is here", range: previous)])
            } else {
                seenWireNames[definition.wireName] = caseSyntax.name.range
            }

            cases.append(definition)
        }

        return UnionDefinition(name: syntax.name.text, cases: cases,
                               discriminator: attributes.discriminator ?? UnionDefinition.defaultDiscriminator,
                               isRecursive: false,
                               documentation: syntax.documentation.map(\.text),
                               deprecation: attributes.deprecation,
                               sourceFile: file, origin: syntax.range)
    }

    private mutating func lowerAlias(_ syntax: TypeAliasSyntax,
                                     in file: SourceFileID,
                                     diagnostics: inout DiagnosticBag) -> AliasDefinition? {
        let attributes = AttributeRegistry.resolve(syntax.attributes, target: .alias,
                                                   ownerDescription: "a type alias",
                                                   diagnostics: &diagnostics)
        guard !syntax.target.containsMissing else { return nil }

        let target = resolve(syntax.target, diagnostics: &diagnostics)
        aliasTargets[syntax.name.text] = target

        return AliasDefinition(name: syntax.name.text, target: target,
                               documentation: syntax.documentation.map(\.text),
                               deprecation: attributes.deprecation,
                               sourceFile: file, origin: syntax.range)
    }

    // MARK: Type resolution

    private func resolve(_ type: TypeSyntax, diagnostics: inout DiagnosticBag) -> TypeRef {
        switch type {
        case .named(let identifier):
            resolveName(identifier, diagnostics: &diagnostics)
        case .optional(let wrapped, _):
            .optional(resolve(wrapped, diagnostics: &diagnostics))
        case .list(let element, _):
            .list(resolve(element, diagnostics: &diagnostics))
        case .set(let element, _):
            .set(resolve(element, diagnostics: &diagnostics))
        case .map(let key, let value, _):
            .map(key: resolve(key, diagnostics: &diagnostics),
                 value: resolve(value, diagnostics: &diagnostics))
        case .missing:
            .unresolved("")
        }
    }

    private func resolveName(_ identifier: IdentifierSyntax,
                             diagnostics: inout DiagnosticBag) -> TypeRef {
        let name = identifier.text

        // `Int` is deliberately not a type. It would mean 64 bits in Swift and 32 in
        // Kotlin, so a server-issued identifier could decode on iOS and overflow on
        // Android with nothing in the schema to warn you.
        if name == ScalarType.rejectedIntegerName {
            diagnostics.error(.ambiguousIntWidth,
                              "'Int' is not a type in this language because its width differs between Swift and Kotlin",
                              at: identifier.range,
                              notes: [.init(message: "use 'Int64' for identifiers and counts from a server, or 'Int32' when you specifically want 32 bits")],
                              fixIts: [
                                .init(message: "use 'Int64'", range: identifier.range, replacement: "Int64"),
                                .init(message: "use 'Int32'", range: identifier.range, replacement: "Int32")
                              ])
            return .unresolved(name)
        }

        guard let symbol = symbols[name] else {
            var notes: [Diagnostic.Note] = []
            if let suggestion = NameSuggestion.closest(to: name, among: symbols.suggestableNames) {
                notes.append(.init(message: "did you mean '\(suggestion)'?"))
            }
            diagnostics.error(.unknownType, "unknown type '\(name)'",
                              at: identifier.range, notes: notes)
            return .unresolved(name)
        }

        switch symbol.kind {
        case .scalar(let scalar):
            return .scalar(scalar)
        case .container:
            diagnostics.error(.genericArity,
                              "'\(name)' needs type arguments",
                              at: identifier.range,
                              notes: [.init(message: name == "Set" ? "write 'Set<Element>'" : "write 'Map<Key, Value>'")])
            return .unresolved(name)
        case .model, .enum, .union, .alias:
            return .named(name, symbol.kind.namedKind!)
        }
    }

    // MARK: Post-pass checks

    /// A union's payload must be a model, because the wire format inlines the payload's
    /// own fields beside the discriminator — there is nothing to inline for a scalar, a
    /// list or an enum.
    private func checkUnionPayloads(in types: [TypeDefinition],
                                    diagnostics: inout DiagnosticBag) {
        for type in types {
            guard case .union(let union) = type else { continue }

            for unionCase in union.cases {
                guard let payloadRange = unionCase.payloadOrigin else { continue }

                guard case .named(let payloadName, let kind) = unionCase.payload else {
                    // An unresolved name has already been reported as an unknown type.
                    if case .unresolved = unionCase.payload { continue }
                    diagnostics.error(.invalidUnionPayload,
                                      "the payload of '\(unionCase.name)' must be a model, but it is \(unionCase.payload.described)",
                                      at: payloadRange,
                                      notes: [.init(message: "the discriminator is written alongside the payload's own fields, so the payload needs fields of its own")])
                    continue
                }

                guard kind == .model else {
                    diagnostics.error(.invalidUnionPayload,
                                      "the payload of '\(unionCase.name)' must be a model, but '\(payloadName)' is \(article(kind)) \(kind.rawValue)",
                                      at: payloadRange,
                                      notes: [.init(message: "wrap it in a model with a single field if you need it in a union")])
                    continue
                }

                // The discriminator key shares the JSON object with the payload's fields,
                // so a field of the same name would overwrite it.
                if let model = modelsByName[payloadName],
                   let clashing = model.fields.first(where: { $0.isSerialized && $0.wireName == union.discriminator }) {
                    var notes: [Diagnostic.Note] = [
                        .init(message: "rename the field, give it a different '@json' name, or set a different '@discriminator' on '\(union.name)'")
                    ]
                    if let fieldOrigin = clashing.origin {
                        notes.append(.init(message: "the field is declared here", range: fieldOrigin))
                    }
                    diagnostics.error(.discriminatorClash,
                                      "'\(payloadName).\(clashing.name)' collides with the discriminator key '\(union.discriminator)' of union '\(union.name)'",
                                      at: payloadRange,
                                      notes: notes)
                }
            }
        }
    }

    /// A model that is a payload in more than one union must be tagged the same way in
    /// each of them.
    ///
    /// Kotlin puts the discriminator value on the payload class itself — one `@SerialName`
    /// per class — so two unions disagreeing about what to call the same model cannot both
    /// be satisfied. Swift would not care, but the language has to mean one thing.
    private func checkPayloadTagConsistency(in types: [TypeDefinition],
                                            diagnostics: inout DiagnosticBag) {
        var tags: [String: (tag: String, union: String, range: SourceRange)] = [:]

        for type in types {
            guard case .union(let union) = type else { continue }
            for unionCase in union.cases {
                guard case .named(let payload, .model) = unionCase.payload,
                      let range = unionCase.payloadOrigin else { continue }

                if let existing = tags[payload], existing.tag != unionCase.wireName {
                    diagnostics.error(.invalidUnionPayload,
                                      "'\(payload)' is tagged '\(unionCase.wireName)' in '\(union.name)' but '\(existing.tag)' in '\(existing.union)'",
                                      at: range,
                                      notes: [
                                        .init(message: "a model carries one discriminator value, so every union using it must agree"),
                                        .init(message: "the other union tags it here", range: existing.range)
                                      ])
                } else if tags[payload] == nil {
                    tags[payload] = (unionCase.wireName, union.name, range)
                }
            }
        }
    }

    /// Detect self-containing types, and mark the unions that need Swift's `indirect`.
    private func applyRecursionRules(to types: [TypeDefinition],
                                     diagnostics: inout DiagnosticBag) -> [TypeDefinition] {
        var containment: [String: Set<String>] = [:]
        var kinds: [String: NamedKind] = [:]

        for type in types {
            kinds[type.name] = type.kind
            switch type {
            case .model(let model):
                containment[model.name] = model.fields.reduce(into: Set()) {
                    $0.formUnion(directlyContainedNames(of: $1.type))
                }
            case .union(let union):
                containment[union.name] = union.cases.reduce(into: Set()) {
                    $0.formUnion(directlyContainedNames(of: $1.payload))
                }
            case .alias(let alias):
                containment[alias.name] = directlyContainedNames(of: alias.target)
            case .enum(let definition):
                containment[definition.name] = []
            }
        }

        let result = RecursionChecker.check(containment: containment, kinds: kinds)

        for cycle in result.illegalModelCycles {
            let names = cycle.joined(separator: " → ")
            for name in cycle {
                guard case .model(let model)? = types.first(where: { $0.name == name }),
                      let origin = model.origin else { continue }
                let description = cycle.count == 1
                    ? "'\(name)' contains itself"
                    : "'\(name)' contains itself through \(names)"
                diagnostics.error(.recursiveModel, description, at: origin,
                                  notes: [.init(message: "a model cannot contain itself directly; put it in a list, a set, a map, or a union")])
            }
        }

        guard !result.recursiveUnions.isEmpty else { return types }

        return types.map { type in
            guard case .union(let union) = type, result.recursiveUnions.contains(union.name) else {
                return type
            }
            return .union(UnionDefinition(name: union.name, cases: union.cases,
                                          discriminator: union.discriminator,
                                          isRecursive: true,
                                          documentation: union.documentation,
                                          deprecation: union.deprecation,
                                          sourceFile: union.sourceFile,
                                          origin: union.origin))
        }
    }

    /// Names reachable without passing through a collection.
    ///
    /// A list, set or map stores its elements out of line on both platforms, so it breaks
    /// a containment cycle and is deliberately not followed here.
    private func directlyContainedNames(of type: TypeRef) -> Set<String> {
        switch type {
        case .named(let name, _): [name]
        case .optional(let wrapped): directlyContainedNames(of: wrapped)
        case .scalar, .unresolved, .list, .set, .map: []
        }
    }

    // MARK: Helpers

    private func warnIfReserved(name: String, range: SourceRange,
                                what: String, diagnostics: inout DiagnosticBag) {
        let platforms = ReservedNames.platformsReserving(name)
        guard !platforms.isEmpty else { return }
        diagnostics.warning(.reservedName,
                            "'\(name)' is a keyword in \(platforms.joined(separator: " and "))",
                            at: range,
                            notes: [.init(message: "the generated code escapes it with backticks, so this \(what) still works")])
    }

    private func article(_ kind: NamedKind) -> String {
        kind == .enum || kind == .alias ? "an" : "a"
    }
}
