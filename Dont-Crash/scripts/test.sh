#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if ! xcodebuild -version >/dev/null 2>&1; then
    echo "Full Xcode unavailable; running identical assertions with the portable runner."
    exec "$ROOT/scripts/test-portable.sh"
fi
mkdir -p "$ROOT/build/module-cache"
export CLANG_MODULE_CACHE_PATH="$ROOT/build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT/build/module-cache"
swift test --package-path "$ROOT" --scratch-path "$ROOT/build/tests" --cache-path "$ROOT/build/spm-cache" --config-path "$ROOT/build/spm-config" --security-path "$ROOT/build/spm-security" -Xswiftc -module-cache-path -Xswiftc "$ROOT/build/module-cache"
