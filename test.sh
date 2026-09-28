#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$PROJECT_DIR/.build"
TEST_APP="$BUILD_DIR/ServiceTests.app"
mkdir -p "$TEST_APP/Contents/MacOS" "$TEST_APP/Contents/Resources"
cp "$PROJECT_DIR/Resources/Info.plist" "$TEST_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleExecutable service-tests' "$TEST_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier local.handoff-watcher.tests' "$TEST_APP/Contents/Info.plist"
for language in en zh-Hans; do
    ditto "$PROJECT_DIR/Resources/$language.lproj" "$TEST_APP/Contents/Resources/$language.lproj"
done
xcrun swiftc -swift-version 5 -module-cache-path "$BUILD_DIR/module-cache" "$PROJECT_DIR/Sources/Localization.swift" "$PROJECT_DIR/Sources/Services.swift" "$PROJECT_DIR/Tests/ServicesTests.swift" -o "$TEST_APP/Contents/MacOS/service-tests"
"$TEST_APP/Contents/MacOS/service-tests"
python3 "$PROJECT_DIR/Tests/LocalizationTests.py" "$TEST_APP/Contents/MacOS/service-tests" "$PROJECT_DIR"
python3 "$PROJECT_DIR/Tests/PackageTests.py" "$PROJECT_DIR"
