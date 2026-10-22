#!/bin/bash
# Synthetic bridge tests plus the real app/Widget build; no device installation or real data mutation.
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
validation_root="${TASKAPP_VALIDATION_ROOT:-$(mktemp -d "${TMPDIR:-/tmp}/CalendarTaskApp-validation.XXXXXX")}"
mkdir -p "$validation_root"
(cd "$project_root/Integrations/DotLocalBridge" && python3 -m unittest -q)
swift test --package-path "$project_root/Integrations/DotLocalBridge" \
    --scratch-path "$validation_root/swift-build" --cache-path "$validation_root/swift-cache" \
    --config-path "$validation_root/swift-config" --security-path "$validation_root/swift-security"
xcodebuild -project "$project_root/CalendarTaskApp.xcodeproj" -scheme CalendarTaskApp \
    -sdk iphonesimulator -derivedDataPath "$validation_root/DerivedData" build
printf 'Validation artifacts retained at %s; no Simulator created or device installed.\n' "$validation_root"
