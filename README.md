
# ModelForge

A macOS developer tool for defining shared data models once and generating idiomatic
Swift and Kotlin from them, so an iOS app and an Android app can agree on their model
layer without hand-syncing two sets of types.

You write models in a small declarative DSL. The app compiles them as you type and shows
the generated Swift and Kotlin beside the source.

```
/// A registered user of the application.
model User {
    @json("user_id")
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

The language is specified in [Docs/shared-data-model-dsl-proposal.md](Docs/shared-data-model-dsl-proposal.md).

## Projects

A ModelForge project is a `.modelforge` file package containing:

```
MyModels.modelforge/
    Config.json      emitter settings, edited in the app's Project Settings
    Manifest.json    what was last generated, so renames do not leave stale files behind
    user.model       ─┐
    common.model      ├─ plain UTF-8 text, one flat namespace, no imports
    payments.model   ─┘
```

Every `.model` file in a project shares a single namespace, so types refer to each other
freely and the language has no `import`. The files themselves stay plain text, so `grep`,
`git diff` and any other editor still work on them.

## Generating

**File ▸ Generate** (⌘B) writes one `.swift` and one `.kt` per model file into the output
folders set in Project Settings, plus a `ModelForgeSupport` file for each language. Those paths are stored relative to the project, so they
keep working after a rename and for anyone else who clones the repository.

Generation is deterministic: the same input produces byte-identical output, and a file
whose contents have not changed is left untouched, which keeps Xcode and Gradle from
rebuilding for no reason. Files that a previous run wrote and this one did not are
deleted, so renaming a model does not leave an orphaned type compiling into your apps.

Generate is disabled while the project has errors.

## The support file

Some scalars have no representation the two platforms agree on out of the box, so
ModelForge generates the coders rather than asking your apps to configure their JSON
encoders correctly:

| Type | On the wire | Why it needs help |
|---|---|---|
| `Instant` | `YYYY-MM-DDThh:mm:ssZ` | Swift's `Date` encodes a number of seconds from 2001; kotlinx writes an ISO string. Swift cannot decode Kotlin's payload at all. |
| `Duration` | `PT1M30S` | Swift encodes a two-element component array; kotlinx writes ISO-8601. |
| `Date` | `YYYY-MM-DD` | Swift has no date-only type, and Kotlin's usual answer is a `kotlinx-datetime` dependency your project may not have. Both get a generated `ModelForgeDate`. |
| `Decimal` | a JSON number | kotlinx has no serializer for `BigDecimal`, so the generated Kotlin would not compile. |

Supplying these ourselves also means the generated Kotlin needs **no `kotlinx-datetime`**
and compiles against **kotlinx-serialization 1.8** as well as 1.9 — 1.9 is only required if
you rely on its built-in `kotlin.time.Instant` serializer, which ModelForge does not.

A model that uses none of these keeps Swift's synthesized `Codable` and stays untouched.

`UUID` is deliberately left alone: Swift writes it uppercase and Kotlin lowercase, but both
parse either, so forcing a coder onto every model holding an identifier would cost more
than the difference does.

## Identity

`@identifiable` conforms a model to Swift's `Identifiable`, which is what SwiftUI lists
want:

```
@identifiable
model User {
    id: UUID
    name: String
}

@identifiable("code")
model Country {
    code: String
    name: String
}
```

The first uses its own `id` field. The second names another field and gets a bridging
`var id: String { code }`. It is deliberately opt-in per model rather than a project-wide
setting: a model with no suitable field would produce Swift that does not compile, so
ModelForge refuses at the schema instead — naming the fields the model does have, or
suggesting the one you meant.

Swift only. Kotlin has no equivalent and ignores it.

## One layout

There is a single canonical style and no options, because a schema shared by two app teams
should never show a diff just because somebody's editor indents differently. **Edit ▸ Format
Model Files** (⌃⌘F) in the app, or `modelgen format`.

It refuses to touch a file that does not parse — rewriting source from a guess at what was
meant is how a formatter destroys work — and it keeps every comment, including trailing
ones. Formatting never changes what a file means, which the tests check by comparing the IR
before and after.

## Enums a server owns

A closed enum fails the **whole payload** when a backend sends a case the client was never
compiled with — not just that field. `@extensible` accepts it and keeps the raw value:

```
@extensible
enum UserStatus {
    active
    suspended
}
```

Swift gets a `RawRepresentable` struct and Kotlin a `@JvmInline value class`, because
neither language's enum can hold a case it was not compiled with. Both decode an unfamiliar
value and write it back untouched, so a client that re-sends an object does not quietly
rewrite a status it did not understand.

The cost is exhaustive switching, which an enum that may grow cannot honestly offer anyway.
Closed enums are still the default — use `@extensible` for anything a server owns.

## Two things the language does deliberately differently

**There is no `Int`.** It would mean 64 bits in Swift and 32 in Kotlin, so a
server-issued identifier could decode on iOS and overflow on Android with nothing in the
schema to warn you. Write `Int32` or `Int64` and get exactly that on both platforms.

**A default means the key may be absent.** `archived: Bool = false` decodes successfully
from a payload that omits `archived`, on both platforms. Without this, the same schema
would behave differently on each — Swift's synthesized `Codable` throws on a missing key
while kotlinx applies the default.

## From a build script

`modelgen` is the same compiler without the app, for build scripts and CI:

```bash
swift build -c release --product modelgen --package-path Packages/ModelForgeKit
```

```
modelgen check                  # compile and report problems, write nothing
modelgen build                  # regenerate into the configured output folders
modelgen build --verify         # fail if the generated code on disk is out of date
modelgen format                 # rewrite the .model files in the canonical layout
modelgen format --verify        # fail if any file is not canonical
modelgen dump-ir                # print the normalized IR
```

Run it from the folder holding your `.modelforge` bundle, or name the bundle. It reads the
same `Config.json` the app does, so output paths need no repeating.

`--verify` is the one worth wiring into CI. Generated code is committed, so a schema change
nobody regenerated would otherwise drift silently:

```
$ modelgen build --verify
update android/models/User.kt
update ios/Generated/User.swift
modelgen: Demo: generated code is out of date (2 file(s)).
Run 'modelgen build' and commit the result.
```

Exit status is 0 for success, 1 for a broken schema or stale output, and 2 when the project
or the arguments could not be understood. Diagnostics print in the same caret format the
app's problems list uses, so a build log reads the way the editor does.

## Letting an agent drive it

ModelForge can expose the projects you have open to a coding agent over the Model Context
Protocol. Turn it on in **Settings ▸ Agents**, then:

```bash
claude mcp add --transport http modelforge http://127.0.0.1:8124/mcp
```

The agent can list and read your model files, check a change before committing to it,
write files, adjust the emitter settings and run Generate. Anything it changes appears in
the open window straight away, so you watch the model and the generated code update as it
works.

Thirteen tools, the useful ones being `check_model_source` (compile a candidate version of
a file without saving it), `write_model_file`, `get_diagnostics` and `generate`. The
server's instructions carry a compact reference for the DSL, so the agent writes valid
syntax without having to discover it by trial and error.

The server binds `127.0.0.1` only and is never reachable from another machine. It is off
by default.

## Building

```bash
open ModelForge.xcodeproj
```

The compiler lives in `Packages/ModelForgeKit`, a dependency-free local package with no UI
in it. Run its tests directly:

```bash
cd Packages/ModelForgeKit && swift test
```

The generated Swift is type-checked against the real compiler as part of the suite, gated
behind an environment variable because it shells out:

```bash
cd Packages/ModelForgeKit && MODELFORGE_COMPILE_TESTS=1 swift test
```

Kotlin needs a JVM toolchain, so it is checked separately — the script uses the compiler
and JDK bundled with Android Studio and the kotlinx-serialization jars already in your
Gradle cache, so there is nothing to install:

```bash
./scripts/verify-kotlin-fixtures.sh
```

## License

See the LICENSE file for licensing information.
