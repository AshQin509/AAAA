#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/build/module-cache"
swiftc -swift-version 5 -parse-as-library -module-cache-path "$ROOT/build/module-cache" "$ROOT/Sources/CodeCoach/WindowChrome.swift" "$ROOT/Validation/WindowInteractionTests.swift" -o "$ROOT/build/WindowInteractionTests"
"$ROOT/build/WindowInteractionTests"
