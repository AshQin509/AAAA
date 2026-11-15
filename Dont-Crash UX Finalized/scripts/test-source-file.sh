#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/build/module-cache"
swiftc -swift-version 5 -parse-as-library -module-cache-path "$ROOT/build/module-cache" "$ROOT"/Sources/CodeCoachCore/*.swift "$ROOT/Sources/CodeCoach/EditorReader.swift" "$ROOT/Validation/SourceFileTests.swift" -lsqlite3 -o "$ROOT/build/SourceFileTests"
"$ROOT/build/SourceFileTests"
