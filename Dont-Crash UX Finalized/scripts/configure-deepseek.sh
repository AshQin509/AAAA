#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$ROOT/scripts/build-app.sh"
"$ROOT/build/CodeCoach.app/Contents/MacOS/CodeCoach" --configure-deepseek
