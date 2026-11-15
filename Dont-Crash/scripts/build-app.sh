#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
APP="$BUILD/CodeCoach.app"
ARCH="${ARCH:-$(uname -m)}"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$BUILD/module-cache"
export CLANG_MODULE_CACHE_PATH="$BUILD/module-cache"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
swiftc -O -swift-version 5 -parse-as-library -target "$ARCH-apple-macosx13.0" -sdk "$SDK" -module-cache-path "$BUILD/module-cache" "$ROOT"/Sources/CodeCoachCore/*.swift "$ROOT"/Sources/CodeCoach/*.swift -lsqlite3 -o "$APP/Contents/MacOS/CodeCoach"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
# Optional official JDK Home; release packages bundle it so users need not configure Java.
if [[ -n "${CODECOACH_BUNDLED_JDK:-}" ]]; then
    test -x "$CODECOACH_BUNDLED_JDK/bin/javac"
    ditto "$CODECOACH_BUNDLED_JDK" "$APP/Contents/Resources/JDK"
fi
codesign --force --sign - --options runtime "$APP"
echo "Built $APP"
