import Foundation

/// Rewrites a `.model` file in the one canonical layout.
///
/// The point of having exactly one style (§28) is diffs: a schema shared by two app teams
/// should never show a change because somebody's editor indents differently.
///
/// Structure comes from the syntax tree and comments come from the token stream, reattached
/// by line — the tree keeps documentation comments but not ordinary ones, and losing a
/// `//` note would make the formatter something people avoid running.
///
/// It refuses to format a file that does not parse. Rewriting source from a guess at what
/// the author meant is how a formatter destroys work.
public enum SourceFormatter {

    public enum Failure: Error, Equatable {
        /// The file has lexical or syntactic problems, so its structure is not known.
        case doesNotParse
    }

    public static func format(_ file: SourceFile) throws(Failure) -> String {
        var diagnostics = DiagnosticBag()
        let tokens = Lexer.tokenize(file, diagnostics: &diagnostics)
        let document = Parser.parse(tokens, file: file.id, diagnostics: &diagnostics)

        // Only lexical and syntactic problems matter: an unknown *type* does not affect
        // layout, and refusing to format over one would be unhelpful.
        guard !diagnostics.diagnostics.contains(where: { $0.severity == .error }) else {
            throw .doesNotParse
        }

        var formatter = Formatter(file: file, tokens: tokens)
        return formatter.run(document)
    }

    /// Whether the file is already in canonical form.
    public static func isFormatted(_ file: SourceFile) -> Bool {
        (try? format(file)) == file.text
    }
}

// MARK: - Implementation

private struct Formatter {

    /// A `//` comment, with the line it sat on and whether code preceded it there.
    struct Comment {
        let line: Int
        let text: String
        let isTrailing: Bool
    }

    let file: SourceFile
    private var comments: [Comment]
    private var nextComment = 0
    private var writer = CodeWriter()

    init(file: SourceFile, tokens: [Token]) {
        self.file = file
        var found: [Comment] = []
        var lastCodeLine = 0
        for token in tokens {
            let line = token.range.start.line
            if case .lineComment = token.kind {
                let text = file.text(ofLine: line)
                    .trimmingCharacters(in: .whitespaces)
                let column = token.range.start.column
                found.append(Comment(line: line,
                                     text: String(text.suffix(from: text.startIndex)),
                                     isTrailing: column > 1 && lastCodeLine == line))
            } else if !token.isEndOfFile {
                lastCodeLine = line
            }
        }
        // A trailing comment's text is the whole line; recover just the comment part.
        self.comments = found.map { comment in
            guard comment.isTrailing else { return comment }
            guard let range = comment.text.range(of: "//") else { return comment }
            return Comment(line: comment.line,
                           text: String(comment.text[range.lowerBound...]),
                           isTrailing: true)
        }
    }

    mutating func run(_ document: DocumentSyntax) -> String {
        for (index, declaration) in document.declarations.enumerated() {
            let startLine = leadingLine(of: declaration)
            emitComments(before: startLine)
            if index > 0 { writer.blank() }
            emit(declaration)
        }
        // Anything trailing the last declaration.
        emitComments(before: Int.max)
        return writer.text
    }

    // MARK: Comments

    /// The first line this declaration occupies, counting its documentation and attributes.
    private func leadingLine(of declaration: DeclarationSyntax) -> Int {
        var line = declaration.range.start.line
        for comment in declaration.documentation { line = min(line, comment.range.start.line) }
        for attribute in declaration.attributes { line = min(line, attribute.range.start.line) }
        return line
    }

    /// Emit standalone comments sitting above `line`, keeping a blank line the author
    /// left between them and whatever follows.
    private mutating func emitComments(before line: Int) {
        var lastEmitted: Int?
        while nextComment < comments.count, comments[nextComment].line < line {
            let comment = comments[nextComment]
            nextComment += 1
            guard !comment.isTrailing else { continue }
            if let lastEmitted, comment.line - lastEmitted > 1 { writer.blank() }
            writer.line(comment.text)
            lastEmitted = comment.line
        }
        if let lastEmitted, line != .max, line - lastEmitted > 1 {
            writer.blank()
        }
    }

    /// The line of the next standalone comment, if it sits above `line`.
    private func pendingCommentLine(above line: Int) -> Int? {
        var index = nextComment
        while index < comments.count, comments[index].line < line {
            if !comments[index].isTrailing { return comments[index].line }
            index += 1
        }
        return nil
    }

    /// A comment the author put at the end of a line of code.
    private mutating func takeTrailingComment(on line: Int) -> String? {
        for index in nextComment..<comments.count where comments[index].line == line {
            guard comments[index].isTrailing else { continue }
            return comments[index].text
        }
        return nil
    }

    /// Skip past comments that sat on a line already emitted as part of something else.
    private mutating func dropComments(upTo line: Int) {
        while nextComment < comments.count, comments[nextComment].line <= line {
            nextComment += 1
        }
    }

    // MARK: Declarations

    private mutating func emit(_ declaration: DeclarationSyntax) {
        switch declaration {
        case .model(let model):
            emitTrivia(model.documentation, model.attributes)
            emitBody("model \(model.name.text)", isEmpty: model.fields.isEmpty) { formatter in
                formatter.emitMembers(model.fields.map(Member.field), in: model.range)
            }

        case .enum(let definition):
            emitTrivia(definition.documentation, definition.attributes)
            emitBody("enum \(definition.name.text)", isEmpty: definition.cases.isEmpty) { formatter in
                formatter.emitMembers(definition.cases.map(Member.enumCase), in: definition.range)
            }

        case .union(let union):
            emitTrivia(union.documentation, union.attributes)
            emitBody("union \(union.name.text)", isEmpty: union.cases.isEmpty) { formatter in
                formatter.emitMembers(union.cases.map(Member.unionCase), in: union.range)
            }

        case .typeAlias(let alias):
            emitTrivia(alias.documentation, alias.attributes)
            let text = "typealias \(alias.name.text) = \(SyntaxDumper.describe(alias.target))"
            let trailing = takeTrailingComment(on: alias.range.end.line)
            writer.line(trailing.map { "\(text)  \($0)" } ?? text)
            dropComments(upTo: alias.range.end.line)
        }
    }

    private mutating func emitBody(_ header: String,
                                   isEmpty: Bool,
                                   _ body: (inout Formatter) -> Void) {
        guard !isEmpty else {
            writer.line("\(header) {")
            writer.line("}")
            return
        }
        writer.line("\(header) {")
        var inner = self
        inner.writer = CodeWriter()
        body(&inner)
        for line in inner.writer.text.split(separator: "\n", omittingEmptySubsequences: false).dropLast() {
            writer.line(line.isEmpty ? "" : "    " + line)
        }
        nextComment = inner.nextComment
        writer.line("}")
    }

    // MARK: Members

    private enum Member {
        case field(FieldSyntax)
        case enumCase(EnumCaseSyntax)
        case unionCase(UnionCaseSyntax)

        var documentation: [DocCommentSyntax] {
            switch self {
            case .field(let member): member.documentation
            case .enumCase(let member): member.documentation
            case .unionCase(let member): member.documentation
            }
        }

        var attributes: [AttributeSyntax] {
            switch self {
            case .field(let member): member.attributes
            case .enumCase(let member): member.attributes
            case .unionCase(let member): member.attributes
            }
        }

        var range: SourceRange {
            switch self {
            case .field(let member): member.range
            case .enumCase(let member): member.range
            case .unionCase(let member): member.range
            }
        }

        var text: String {
            switch self {
            case .field(let member):
                var line = "\(member.name.text): \(SyntaxDumper.describe(member.type))"
                if let value = member.defaultValue {
                    line += " = \(SyntaxDumper.describe(value))"
                }
                return line
            case .enumCase(let member):
                return member.name.text
            case .unionCase(let member):
                return "\(member.name.text)(\(SyntaxDumper.describe(member.payload)))"
            }
        }
    }

    private mutating func emitMembers(_ members: [Member], in declaration: SourceRange) {
        var previousEndLine: Int?

        for member in members {
            let startLine = leadingLine(of: member)
            // A comment introducing the member belongs below the separating blank line,
            // not above it, so the gap is measured to whichever comes first.
            let anchor = min(startLine, pendingCommentLine(above: startLine) ?? startLine)

            // One blank line wherever the author separated members, however many they used.
            if let previousEndLine, anchor - previousEndLine > 1 {
                writer.blank()
            }
            emitComments(before: startLine)

            emitTrivia(member.documentation, member.attributes)
            let trailing = takeTrailingComment(on: member.range.end.line)
            writer.line(trailing.map { "\(member.text)  \($0)" } ?? member.text)
            dropComments(upTo: member.range.end.line)
            previousEndLine = member.range.end.line
        }

        // Comments between the last member and the closing brace.
        emitComments(before: declaration.end.line)
    }

    private func leadingLine(of member: Member) -> Int {
        var line = member.range.start.line
        for comment in member.documentation { line = min(line, comment.range.start.line) }
        for attribute in member.attributes { line = min(line, attribute.range.start.line) }
        return line
    }

    private mutating func emitTrivia(_ documentation: [DocCommentSyntax],
                                     _ attributes: [AttributeSyntax]) {
        for comment in documentation {
            writer.line(comment.text.isEmpty ? "///" : "/// \(comment.text)")
        }
        for attribute in attributes {
            writer.line(render(attribute))
        }
    }

    private func render(_ attribute: AttributeSyntax) -> String {
        guard !attribute.arguments.isEmpty else { return "@\(attribute.name.text)" }
        let arguments = attribute.arguments.map { argument -> String in
            let value = SyntaxDumper.describe(argument.value)
            guard let label = argument.label else { return value }
            return "\(label.text): \(value)"
        }
        return "@\(attribute.name.text)(\(arguments.joined(separator: ", ")))"
    }
}
