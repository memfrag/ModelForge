
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

## Two things the language does deliberately differently

**There is no `Int`.** It would mean 64 bits in Swift and 32 in Kotlin, so a
server-issued identifier could decode on iOS and overflow on Android with nothing in the
schema to warn you. Write `Int32` or `Int64` and get exactly that on both platforms.

**A default means the key may be absent.** `archived: Bool = false` decodes successfully
from a payload that omits `archived`, on both platforms. Without this, the same schema
would behave differently on each — Swift's synthesized `Codable` throws on a missing key
while kotlinx applies the default.

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
