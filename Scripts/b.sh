#!/bin/zsh
# Regenerates the project and does a quiet Debug build into build/debug.
cd "$(dirname "$0")/.."
xcodegen generate -q 2>&1 | grep -v "^$"
SCHEME=$(awk '/^name:/ {print $2}' project.yml)
xcodebuild -project "$SCHEME.xcodeproj" -scheme "$SCHEME" -configuration Debug -derivedDataPath build/debug -allowProvisioningUpdates build -quiet 2>&1 | grep -E "error:|warning: [^U]|BUILD FAILED" | sort -u | head -40
exit ${pipestatus[1]}
