# Proposal: Shared Data Model DSL for Swift and Kotlin

## Status

**Draft proposal**

This document proposes a small, declarative domain-specific language (DSL) for defining shared application data models and generating idiomatic Swift and Kotlin code for iOS and Android.

The DSL is intended to act as the source of truth for model structure and serialization semantics while keeping the generated code natural for each platform.

---

## 1. Goals

The DSL should:

- Provide a single source of truth for data model definitions shared between iOS and Android.
- Generate idiomatic Swift and Kotlin types.
- Be easy to read and write by application developers.
- Feel closer to source code than to configuration formats such as YAML or JSON.
- Remain intentionally small and declarative.
- Support common app-model concepts:
  - objects/models
  - enums
  - tagged unions
  - type aliases
  - optional values
  - nullable values
  - collections
  - defaults
  - serialization metadata
  - documentation
  - imports
- Be simple enough to parse with a handwritten lexer and recursive-descent parser.
- Keep syntax separate from code-generation concerns through an intermediate representation.
- Allow the DSL to evolve without tying it too closely to either Swift or Kotlin.

---

## 2. Non-goals

The DSL should not become a general-purpose programming language.

In particular, v1 should not support:

- arbitrary functions
- computed properties
- control flow
- inheritance
- arbitrary Swift code
- arbitrary Kotlin code
- executable expressions beyond simple constant defaults
- platform UI concepts
- persistence-framework-specific behavior
- business logic

The DSL describes data shape and shared semantics. Platform-specific behavior remains in platform code.

---

## 3. Design principles

### 3.1 Declarative rather than executable

A model file should describe what a type is, not how it behaves.

### 3.2 Neutral semantics

The language should describe domain concepts rather than Swift or Kotlin syntax.

For example:

```dsl
createdAt: Instant
```

may map to:

```swift
let createdAt: Date
```

on Swift and:

```kotlin
val createdAt: Instant
```

on Kotlin.

### 3.3 Idiomatic output

Generated code should look as though a native Swift or Kotlin developer could reasonably have written it by hand.

### 3.4 Small core language

Most extensibility should come from metadata/attributes rather than adding many keywords.

### 3.5 Stable intermediate representation

The parser should not emit Swift or Kotlin directly.

Recommended pipeline:

```text
source
  ↓
lexer
  ↓
parser
  ↓
AST
  ↓
semantic analysis
  ↓
normalized IR
  ↓
Swift emitter
Kotlin emitter
```

---

## 4. File format

Suggested extension:

```text
.model
```

Alternative names could be considered later, for example:

```text
.schema
.sharedmodel
.mdl
```

Example:

```dsl
import "./common.model"

/// A registered application user.
model User {
    id: UUID
    name: String
    email: String?
    status: UserStatus
    createdAt: Instant
}

enum UserStatus {
    active
    suspended
    deleted
}
```

---

## 5. Core syntax

## 5.1 Models

```dsl
model User {
    id: UUID
    name: String
    email: String?
}
```

Generated Swift:

```swift
struct User: Codable, Equatable, Sendable {
    let id: UUID
    let name: String
    let email: String?
}
```

Generated Kotlin:

```kotlin
@Serializable
data class User(
    val id: Uuid,
    val name: String,
    val email: String?,
)
```

---

## 5.2 Enums

```dsl
enum UserStatus {
    active
    suspended
    deleted
}
```

Swift:

```swift
enum UserStatus: String, Codable, Sendable {
    case active
    case suspended
    case deleted
}
```

Kotlin:

```kotlin
@Serializable
enum class UserStatus {
    ACTIVE,
    SUSPENDED,
    DELETED,
}
```

The serialized value should remain the DSL value unless explicitly overridden.

---

## 5.3 Tagged unions

```dsl
union PaymentMethod {
    card(Card)
    applePay(ApplePay)
    bankAccount(BankAccount)
}
```

Swift:

```swift
enum PaymentMethod {
    case card(Card)
    case applePay(ApplePay)
    case bankAccount(BankAccount)
}
```

Kotlin:

```kotlin
sealed interface PaymentMethod {
    data class Card(val value: CardModel) : PaymentMethod
    data class ApplePay(val value: ApplePayModel) : PaymentMethod
    data class BankAccount(val value: BankAccountModel) : PaymentMethod
}
```

Exact generated naming can be configurable at the emitter level.

For serialized unions, a discriminator can be specified:

```dsl
@discriminator("type")
union PaymentMethod {
    card(Card)
    applePay(ApplePay)
    bankAccount(BankAccount)
}
```

Example wire representation:

```json
{
  "type": "card",
  "number": "..."
}
```

---

## 5.4 Type aliases

```dsl
typealias UserID = UUID
typealias EmailAddress = String
```

Possible Swift output:

```swift
typealias UserID = UUID
typealias EmailAddress = String
```

Possible Kotlin output:

```kotlin
typealias UserID = Uuid
typealias EmailAddress = String
```

Whether aliases remain true aliases or generate wrapper types could later be controlled through an attribute.

---

## 5.5 Imports

```dsl
import "./common.model"
import "./user.model"
```

Imports are resolved relative to the current file unless otherwise configured.

The compiler should construct a module graph and detect:

- missing imports
- duplicate definitions
- ambiguous symbols
- illegal import cycles, if any cycle restrictions are introduced

Import cycles do not necessarily need to be forbidden if the semantic model can resolve them safely.

---

## 6. Type system

The initial built-in type set should remain deliberately small.

### 6.1 Primitive scalar types

```text
String
Bool
Int
Int32
Int64
Float
Double
Decimal
UUID
URL
Date
Instant
Duration
```

Recommended semantics:

| DSL type | Swift | Kotlin |
|---|---|---|
| `String` | `String` | `String` |
| `Bool` | `Bool` | `Boolean` |
| `Int` | `Int` | `Int` |
| `Int32` | `Int32` | `Int` |
| `Int64` | `Int64` | `Long` |
| `Float` | `Float` | `Float` |
| `Double` | `Double` | `Double` |
| `Decimal` | `Decimal` | configurable, e.g. `BigDecimal` |
| `UUID` | `UUID` | `Uuid` |
| `URL` | `URL` | configurable URI/URL type |
| `Date` | app-defined date-only type | `LocalDate` |
| `Instant` | `Date` or custom instant type | `Instant` |
| `Duration` | `Duration` or custom type | `Duration` |

The exact platform mapping belongs in each emitter rather than in the parser.

---

## 6.2 Optional types

```dsl
email: String?
```

Normalized representation:

```text
Optional(
    Named("String")
)
```

Swift:

```swift
let email: String?
```

Kotlin:

```kotlin
val email: String?
```

---

## 6.3 Collections

Lists:

```dsl
users: [User]
```

Sets:

```dsl
tags: Set<String>
```

Maps:

```dsl
metadata: Map<String, String>
```

Nested types are valid:

```dsl
groups: [[User]]
usersByID: Map<UUID, User>
optionalUsers: [User?]
```

---

## 7. Optional vs nullable vs presence

This distinction should be designed explicitly.

For serialized data, these states can be different:

```json
{}
```

```json
{
  "name": null
}
```

```json
{
  "name": "Martin"
}
```

A simple `String?` may not preserve all three states.

Recommended DSL distinction:

```dsl
name: String?
```

means the field value may be null.

Presence can be expressed separately:

```dsl
@optional
name: String
```

Or, more explicitly:

```dsl
@presence(optional)
name: String
```

A field could therefore be both optional-in-presence and nullable:

```dsl
@presence(optional)
name: String?
```

Semantically:

```text
missing
present(null)
present(value)
```

The generators may use a wrapper when the distinction matters.

Example conceptual Swift type:

```swift
enum Field<Value> {
    case missing
    case value(Value)
}
```

Example conceptual Kotlin type:

```kotlin
sealed interface Field<out T> {
    data object Missing : Field<Nothing>
    data class Value<T>(val value: T) : Field<T>
}
```

For ordinary application models, generators may collapse presence semantics where explicitly configured.

---

## 8. Default values

Simple literal defaults should be supported:

```dsl
model Project {
    name: String
    archived: Bool = false
    retryCount: Int = 0
    tags: [String] = []
}
```

Suggested supported defaults in v1:

- string literals
- integer literals
- floating-point literals
- booleans
- `null`
- empty list
- empty set
- empty map
- enum cases

Example:

```dsl
status: UserStatus = .active
```

Arbitrary expressions should not be supported.

---

## 9. Attributes

Attributes provide controlled extensibility without bloating the grammar.

Syntax:

```dsl
@attribute
@attribute("value")
@attribute(name: "value", enabled: true)
```

Example:

```dsl
@serializable
model User {
    @json("user_id")
    id: UUID

    @deprecated
    username: String?

    @transient
    isSelected: Bool = false
}
```

Attributes should be parsed generically, then validated semantically.

---

## 10. Suggested standard attributes

### 10.1 Serialization name

```dsl
@json("user_id")
id: UUID
```

Swift may generate coding keys.

Kotlin may generate:

```kotlin
@SerialName("user_id")
```

### 10.2 Serialization exclusion

```dsl
@transient
isSelected: Bool = false
```

This field exists in native models but is excluded from wire serialization.

### 10.3 Deprecation

```dsl
@deprecated
oldName: String?
```

or:

```dsl
@deprecated("Use displayName instead")
oldName: String?
```

### 10.4 Discriminator

```dsl
@discriminator("type")
union Event {
    message(MessageEvent)
    image(ImageEvent)
}
```

### 10.5 Serialization behavior

```dsl
@serializable
model User {
    ...
}
```

Whether serialization is default-on or opt-in should be decided before v1.

A reasonable default is that all generated models are serializable unless marked otherwise.

---

## 11. Documentation comments

Documentation should be preserved and emitted into generated code.

Syntax:

```dsl
/// A registered application user.
model User {
    /// Stable server-generated identifier.
    id: UUID

    /// Name shown in the UI.
    displayName: String
}
```

Swift:

```swift
/// A registered application user.
struct User {
    /// Stable server-generated identifier.
    let id: UUID
}
```

Kotlin:

```kotlin
/**
 * A registered application user.
 */
data class User(
    /** Stable server-generated identifier. */
    val id: Uuid,
)
```

Only documentation comments beginning with `///` need to be supported initially.

---

## 12. Naming

The DSL should preserve logical names and allow emitters to apply platform conventions.

Example:

```dsl
enum HTTPMethod {
    get
    post
    put
    delete
}
```

Swift could preserve case names:

```swift
enum HTTPMethod {
    case get
    case post
    case put
    case delete
}
```

Kotlin could generate uppercase enum constants:

```kotlin
enum class HTTPMethod {
    GET,
    POST,
    PUT,
    DELETE,
}
```

Serialization should still use the logical DSL name unless overridden.

---

## 13. Proposed grammar

A simplified EBNF sketch:

```ebnf
document        = importDecl* declaration* EOF ;

importDecl      = "import" STRING ;

declaration     = docComment*
                  attribute*
                  (
                    modelDecl
                  | enumDecl
                  | unionDecl
                  | typealiasDecl
                  ) ;

modelDecl       = "model" IDENT "{"
                    fieldDecl*
                  "}" ;

fieldDecl       = docComment*
                  attribute*
                  IDENT ":" type defaultValue? ;

enumDecl        = "enum" IDENT "{"
                    enumCase*
                  "}" ;

enumCase        = docComment*
                  attribute*
                  IDENT ;

unionDecl       = "union" IDENT "{"
                    unionCase*
                  "}" ;

unionCase       = docComment*
                  attribute*
                  IDENT "(" type ")" ;

typealiasDecl   = "typealias" IDENT "=" type ;

type            = primaryType nullableSuffix? ;

primaryType     = IDENT
                | "[" type "]"
                | "Set" "<" type ">"
                | "Map" "<" type "," type ">" ;

nullableSuffix  = "?" ;

defaultValue    = "=" literal ;

attribute       = "@" IDENT attributeArguments? ;

attributeArguments
                = "(" argumentList? ")" ;

argumentList    = argument ("," argument)* ;

argument        = literal
                | IDENT ":" literal ;

literal         = STRING
                | INTEGER
                | FLOAT
                | "true"
                | "false"
                | "null"
                | "[]"
                | "{}"
                | "." IDENT ;
```

This grammar is intentionally incomplete around whitespace, comments, escaping, and detailed literal syntax.

---

## 14. Lexer

The lexer likely needs only a small token set.

Suggested token categories:

```text
Identifier
StringLiteral
IntegerLiteral
FloatLiteral

model
enum
union
typealias
import
true
false
null

{
}
(
)
[
]
<
>
:
,
=
?
@
.
```

Comments:

```text
// regular comment
/// documentation comment
```

Block comments can be deferred unless clearly useful.

---

## 15. Parser

A handwritten recursive-descent parser should be sufficient.

Example shape:

```text
parseDocument()
parseImport()
parseDeclaration()
parseModel()
parseEnum()
parseUnion()
parseTypeAlias()
parseField()
parseType()
parseAttribute()
parseLiteral()
```

Advantages:

- easy to debug
- easy to produce custom error messages
- no parser-generator dependency
- grammar remains understandable
- straightforward recovery for editor tooling later

---

## 16. AST

The parser should produce a syntax-oriented AST.

Conceptually:

```text
Document
  imports: [Import]
  declarations: [Declaration]

Declaration
  ModelDeclaration
  EnumDeclaration
  UnionDeclaration
  TypeAliasDeclaration

ModelDeclaration
  name
  documentation
  attributes
  fields

FieldDeclaration
  name
  typeSyntax
  defaultSyntax
  documentation
  attributes
```

The AST should retain source locations for all meaningful nodes.

Example:

```text
SourceRange
  file
  startLine
  startColumn
  endLine
  endColumn
```

This is essential for useful compiler diagnostics.

---

## 17. Semantic analysis

The semantic analysis phase should handle:

- symbol resolution
- import resolution
- duplicate declaration checks
- duplicate field checks
- unknown type detection
- generic arity validation
- attribute validation
- default-value type checking
- union-case validation
- serialization constraints
- recursive-type handling
- reserved-name handling

Example diagnostic:

```text
models/user.model:8:12

    manager: Usre?
             ^^^^

error: unknown type 'Usre'
help: did you mean 'User'?
```

Diagnostics should be treated as a first-class product feature.

---

## 18. Intermediate representation

The code generators should consume a normalized IR, not the parser AST.

Example conceptual IR:

```text
Module
  types: [TypeDefinition]

TypeDefinition
  Model
  Enum
  Union
  Alias

Model
  name
  fields
  documentation
  serialization

Field
  name
  type
  defaultValue
  presence
  serializedName
  transient

Type
  Scalar
  Named
  Optional
  List
  Set
  Map
```

Example:

```dsl
users: [User?]
```

normalizes to:

```text
List(
    Optional(
        Named("User")
    )
)
```

This keeps syntax quirks out of generators.

---

## 19. Swift emitter

The Swift emitter should own decisions such as:

- `struct` vs `class`
- protocol conformances
- `let` vs `var`
- `Codable`
- `Sendable`
- `Equatable`
- `Hashable`
- date representation
- URL representation
- coding keys
- generated serializers for unions
- naming transformations

Recommended default model output:

```swift
struct User: Codable, Equatable, Sendable {
    let id: UUID
    let name: String
    let email: String?
    let status: UserStatus
    let createdAt: Date
}
```

Generated files should include a standard header:

```swift
// Generated file. Do not edit manually.
```

---

## 20. Kotlin emitter

The Kotlin emitter should own decisions such as:

- `data class`
- `val` vs `var`
- kotlinx.serialization integration
- enum naming
- sealed interfaces/classes
- `Instant`
- `Uuid`
- `BigDecimal`
- package naming
- generated serializers for unions

Recommended default model output:

```kotlin
@Serializable
data class User(
    val id: Uuid,
    val name: String,
    val email: String?,
    val status: UserStatus,
    val createdAt: Instant,
)
```

Generated files should include:

```kotlin
// Generated file. Do not edit manually.
```

---

## 21. Example end-to-end schema

```dsl
import "./common.model"

/// A user account in the application.
model User {
    /// Stable account identifier.
    @json("user_id")
    id: UUID

    name: String
    email: String?

    status: UserStatus = .active

    createdAt: Instant

    @transient
    isSelected: Bool = false
}

enum UserStatus {
    active
    suspended
    deleted
}

@discriminator("type")
union UserAction {
    renamed(RenameAction)
    changedEmail(ChangeEmailAction)
    deleted(DeleteAction)
}

model RenameAction {
    name: String
}

model ChangeEmailAction {
    email: String
}

model DeleteAction {
    reason: String?
}
```

---

## 22. Suggested project layout

```text
shared-models/
    models/
        common.model
        user.model
        project.model
        messaging.model

    compiler/
        lexer/
        parser/
        semantic/
        ir/
        emitters/
            swift/
            kotlin/

    tests/
        parser/
        semantic/
        swift/
        kotlin/
        fixtures/
```

Generated code might go to:

```text
ios/
    Generated/
        Models/

android/
    app/
        src/
            main/
                generated/
                    models/
```

Exact directories should be configurable.

---

## 23. Build integration

Recommended command-line interface:

```text
modelgen build
```

Possible options:

```text
modelgen build \
    --input shared-models/models \
    --swift-output ios/Generated/Models \
    --kotlin-output android/app/src/main/generated/models
```

Additional commands:

```text
modelgen check
modelgen format
modelgen dump-ir
```

### `modelgen check`

Parses and validates without generating files.

Useful in CI.

### `modelgen format`

Applies canonical formatting to DSL files.

### `modelgen dump-ir`

Prints the normalized intermediate representation for debugging.

---

## 24. Deterministic generation

Code generation should be deterministic.

Given identical:

- schema input
- compiler version
- generator configuration

the output should be byte-for-byte identical.

Generated code should avoid timestamps unless explicitly requested, because timestamps create noisy diffs.

---

## 25. Configuration

Language-wide generation policy should live outside individual model files where possible.

Example:

```toml
[swift]
module = "AppModels"
codable = true
equatable = true
sendable = true
date_type = "Foundation.Date"

[kotlin]
package = "com.example.models"
serialization = "kotlinx"
uuid_type = "kotlin.uuid.Uuid"
instant_type = "kotlin.time.Instant"
```

This avoids filling schemas with emitter-specific annotations.

Platform-specific escape hatches may eventually be necessary, but should be treated as exceptions.

---

## 26. Schema evolution

The compiler should eventually support compatibility checking between schema versions.

Potential changes:

### Usually compatible

- adding an optional field
- adding a field with a safe default
- adding an enum case if clients tolerate unknown values
- adding a union case if clients tolerate unknown variants

### Potentially breaking

- removing a field
- renaming a serialized field
- changing field type
- changing nullability
- making an optional field required
- removing enum cases
- changing union discriminator behavior

A later command could support:

```text
modelgen compatibility old/ new/
```

This does not need to be part of v1.

---

## 27. Enum evolution and unknown values

Network-backed enums need special consideration.

Example:

```dsl
enum UserStatus {
    active
    suspended
}
```

A newer backend might later send:

```json
"deleted"
```

Possible policies:

1. strict decoding
2. generated unknown case
3. unknown raw-value wrapper

This should be a generator-level or schema-level policy.

Example future syntax:

```dsl
@unknownCase
enum UserStatus {
    active
    suspended
}
```

The exact representation can differ between Swift and Kotlin.

---

## 28. Formatting

The project should ship with one canonical formatter.

Example canonical style:

```dsl
model User {
    id: UUID
    name: String
    email: String?
}
```

Rather than supporting many formatting variants, the formatter should make source layout predictable.

Benefits:

- cleaner diffs
- easier generated examples
- simpler tooling
- fewer style debates

---

## 29. Testing strategy

Testing should happen at several layers.

### Lexer tests

Input:

```dsl
email: String?
```

Expected tokens:

```text
Identifier(email)
Colon
Identifier(String)
QuestionMark
```

### Parser snapshot tests

Input DSL → AST snapshot.

### Semantic tests

Examples:

- unknown type
- duplicate field
- invalid default
- invalid attribute
- duplicate enum case

### IR tests

Ensure different syntax forms normalize identically where intended.

### Generator snapshot tests

DSL fixture → exact Swift output.

DSL fixture → exact Kotlin output.

### Compile tests

Generated Swift should be compiled with `swiftc` or the app build.

Generated Kotlin should be compiled with the Kotlin compiler or Gradle build.

These tests are especially valuable because code that looks plausible is not always valid platform code.

---

## 30. Editor tooling

Not required for v1, but source locations and a clean compiler architecture should make later editor support possible.

Potential future features:

- syntax highlighting
- diagnostics
- go-to-definition
- hover documentation
- rename symbol
- completion
- formatting
- Language Server Protocol support

Keeping parsing and semantic analysis independent from the CLI will make this easier.

---

## 31. Minimal v1

A practical v1 should support only:

### Declarations

```text
model
enum
union
typealias
import
```

### Types

```text
String
Bool
Int
Int32
Int64
Float
Double
Decimal
UUID
URL
Date
Instant
Duration
```

### Containers

```text
T?
[T]
Set<T>
Map<K, V>
```

### Other language features

- documentation comments
- simple defaults
- generic attributes
- JSON field-name override
- transient fields
- union discriminator
- source diagnostics
- Swift generation
- Kotlin generation

Avoid adding more until real project usage demonstrates a need.

---

## 32. Features to defer

Potential post-v1 additions:

- generic user-defined models
- wrapper/newtype generation
- validation constraints
- numeric ranges
- regex constraints
- richer serialization strategies
- unknown enum handling policies
- compatibility analysis
- package/module namespaces
- schema versioning
- generated builders
- generated test fixtures
- persistence annotations
- GraphQL/OpenAPI/JSON Schema emitters
- TypeScript generation
- Rust generation
- LSP implementation

---

## 33. Open questions

The following decisions should be made before implementation is finalized.

### Serialization defaults

Should every model be serializable by default, or only models marked with `@serializable`?

Recommended direction: serializable by default.

### Optional vs nullable syntax

Should `T?` mean nullable only, or "field may be absent"?

Recommended direction: `T?` means nullable value; field presence is separate.

### Default Swift `Instant` mapping

Candidates:

- `Foundation.Date`
- a project-defined `Instant`
- Foundation's newer time APIs where appropriate

Recommended direction: configurable emitter mapping, with `Date` as a pragmatic initial default.

### Kotlin UUID mapping

Candidates depend on supported Kotlin version and project libraries.

Recommended direction: emitter configuration.

### Enum unknown values

This matters strongly for network models and should be designed before using the DSL as an API contract.

### Serialization libraries

Swift will likely use `Codable`.

Kotlin will likely use `kotlinx.serialization`.

These should be defaults rather than hard parser-level assumptions.

---

## 34. Recommended implementation approach

The implementation should begin with the smallest complete vertical slice:

1. Lexer
2. Parser for `model`
3. Primitive and optional types
4. AST with source locations
5. Semantic symbol table
6. Normalized IR
7. Swift emitter
8. Kotlin emitter
9. Snapshot tests
10. Add enums
11. Add collections
12. Add imports
13. Add unions
14. Add attributes and serialization metadata
15. Add formatter

This validates the overall architecture before introducing advanced semantics.

---

## 35. Example minimal compiler API

The internal compiler library could expose something conceptually similar to:

```text
compile(
    sources,
    configuration
) -> CompilationResult
```

Where:

```text
CompilationResult
    diagnostics
    module
```

And:

```text
emitSwift(module, configuration)
emitKotlin(module, configuration)
```

The CLI should be a thin wrapper around these APIs.

That makes the compiler reusable from:

- tests
- IDE tooling
- build plugins
- command-line invocation
- future Gradle integration
- future Xcode build tooling

---

## 36. Summary

The proposed DSL is a small, code-like declarative language for describing shared mobile application models.

Example:

```dsl
import "./common.model"

model User {
    id: UUID
    name: String
    email: String?
    status: UserStatus = .active
    createdAt: Instant
}

enum UserStatus {
    active
    suspended
    deleted
}
```

The compiler architecture is:

```text
DSL source
    ↓
Lexer
    ↓
Parser
    ↓
AST
    ↓
Semantic analysis
    ↓
Normalized IR
    ↓
┌──────────────┬──────────────┐
│ Swift emitter│Kotlin emitter│
└──────────────┴──────────────┘
```

The key design constraint is to keep the language focused on shared data semantics while allowing Swift and Kotlin generators to remain independently idiomatic.

For v1, the project should resist feature growth and concentrate on a small, stable type system, excellent diagnostics, deterministic output, and code generation that developers are comfortable using directly in production applications.
