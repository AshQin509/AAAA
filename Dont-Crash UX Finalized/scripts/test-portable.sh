#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/build/module-cache"
swiftc -swift-version 5 -D PORTABLE_TESTS -parse-as-library -module-cache-path "$ROOT/build/module-cache" "$ROOT"/Sources/CodeCoachCore/*.swift "$ROOT/Tests/CodeCoachCoreTests/CoreTests.swift" "$ROOT/Validation/PortableRunner.swift" -lsqlite3 -o "$ROOT/build/CoreTests"
"$ROOT/build/CoreTests"
