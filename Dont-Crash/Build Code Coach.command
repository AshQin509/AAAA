#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
if ./scripts/build-app.sh; then
    echo "Done: open CodeCoach.app in the build folder."
else
    echo "Build failed. Install Xcode or Command Line Tools. See README."
fi
read -r -p "Press Return to close…"
