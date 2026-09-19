import Foundation

/// Turns a resolved module into source text.
///
/// Emitters are deliberately plain string building rather than a template engine. The
/// output has to be byte-identical from one run to the next (§24) and is pinned by
/// exact-output fixtures, and most of the real work — emit `CodingKeys` only when
/// something is renamed, a decoder only when defaults exist, `indirect` only when
/// recursive — is conditional logic a template could only echo after Swift had already
/// worked it out.
protocol Emitter {
    var language: Language { get }

    /// Emit the declarations belonging to one source file.
    ///
    /// The whole module is passed because a declaration's output can depend on the rest of
    /// the project: Kotlin's sealed interfaces need to know which unions a model belongs
    /// to, even when the union is declared in another file.
    func emit(file: SourceFileID, named name: String, from module: Module) -> GeneratedFile
}

extension Emitter {

    /// `user.model` → `User.swift`
    func fileName(forSourceNamed name: String) -> String {
        let stem = name.hasSuffix(".model") ? String(name.dropLast(6)) : name
        return "\(NamingConventions.upperCamelCase(stem)).\(language.fileExtension)"
    }
}
