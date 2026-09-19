#!/bin/bash
set -euo pipefail

# -----------------------------------------------------------------------------
# Compile the generated Kotlin fixtures for real.
#
# The Swift side is type-checked from the test suite itself
# (MODELFORGE_COMPILE_TESTS=1 swift test), but Kotlin needs a JVM toolchain and
# the kotlinx.serialization compiler plugin, which is too heavy to run on every
# `swift test`. Run this whenever the Kotlin emitter or the support file changes,
# and before cutting a release.
#
# This is the only thing that catches output that looks plausible and is not
# valid Kotlin — a missing `f` on a Float default, an opt-in that was never
# declared, a serializer that does not exist for a type.
#
# Uses the Kotlin compiler and JDK bundled with Android Studio, and the
# kotlinx-serialization jars already in the Gradle cache, so there is nothing to
# install and nothing is downloaded unless the cache has no usable version.
# -----------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
FIXTURES="$PROJECT_DIR/Packages/ModelForgeKit/Tests/ModelForgeKitTests/Fixtures/Generation"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

error() { echo "ERROR: $1" >&2; exit 1; }

# --- Toolchain ---------------------------------------------------------------
STUDIO="${ANDROID_STUDIO_APP:-/Applications/Android Studio.app}"
KOTLINC="$STUDIO/Contents/plugins/Kotlin/kotlinc/bin/kotlinc"
PLUGIN="$STUDIO/Contents/plugins/Kotlin/kotlinc/lib/kotlinx-serialization-compiler-plugin.jar"
STDLIB="$STUDIO/Contents/plugins/Kotlin/kotlinc/lib/kotlin-stdlib.jar"
export JAVA_HOME="${JAVA_HOME:-$STUDIO/Contents/jbr/Contents/Home}"

if [ ! -x "$KOTLINC" ]; then
    # Fall back to a standalone install if Android Studio is not where we expect.
    KOTLINC="$(command -v kotlinc || true)"
    [ -n "$KOTLINC" ] || error "No Kotlin compiler found. Install Android Studio, or: brew install kotlin"
    PLUGIN="$(find "$(dirname "$(dirname "$KOTLINC")")/lib" -name 'kotlinx-serialization-compiler-plugin*.jar' | head -1)"
fi
[ -f "$PLUGIN" ] || error "Could not find the kotlinx-serialization compiler plugin."

# --- Runtime jars ------------------------------------------------------------
# The generated code needs kotlinx-serialization only; the support file supplies
# the serializers for everything else, so there is no kotlinx-datetime here.
find_jar() {
    find "$HOME/.gradle/caches/modules-2/files-2.1/org.jetbrains.kotlinx" \
        -name "$1-*.jar" ! -name '*sources*' 2>/dev/null | sort -V | tail -1
}

CORE="$(find_jar kotlinx-serialization-core-jvm)"
JSON="$(find_jar kotlinx-serialization-json-jvm)"

if [ -z "$CORE" ] || [ -z "$JSON" ]; then
    echo "==> kotlinx-serialization not in the Gradle cache; downloading..."
    V="1.8.0"
    M="https://repo1.maven.org/maven2/org/jetbrains/kotlinx"
    for a in kotlinx-serialization-core-jvm kotlinx-serialization-json-jvm; do
        curl -sfL "$M/$a/$V/$a-$V.jar" -o "$WORK_DIR/$a.jar" || error "Could not download $a"
    done
    CORE="$WORK_DIR/kotlinx-serialization-core-jvm.jar"
    JSON="$WORK_DIR/kotlinx-serialization-json-jvm.jar"
fi

CLASSPATH="$CORE:$JSON"
echo "==> kotlinc: $("$KOTLINC" -version 2>&1 | head -1)"
echo "==> serialization: $(basename "$CORE")"

# --- Compile each fixture project as a whole ---------------------------------
# A sealed interface needs its implementations in the same compilation unit, and
# the models reference the support file, so a project compiles together.
status=0
for project in "$FIXTURES"/*/; do
    name="$(basename "$project")"
    files=("$project"expected/*.kt)
    [ -e "${files[0]}" ] || continue

    echo "==> $name (${#files[@]} files)"
    if "$KOTLINC" -Xplugin="$PLUGIN" -classpath "$CLASSPATH" \
        -d "$WORK_DIR/$name" -nowarn "${files[@]}" 2>&1 | sed 's/^/    /'; then
        echo "    OK"
    else
        status=1
    fi
done

[ "$status" -eq 0 ] || error "Generated Kotlin did not compile."
echo "==> All generated Kotlin compiles."
