#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT_DIR="$PROJECT_DIR/outputs"
BUILD_DIR="$PROJECT_DIR/.build"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/handoff-watcher-package.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT
APP_DIR="$STAGING_DIR/HandoffWatcher.app"
mkdir -p "$BUILD_DIR" "$OUTPUT_DIR" "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
EXTRA_FLAGS=(-D HANDOFF_WATCHER_RELEASE)
if [[ "${HANDOFF_WATCHER_QA:-0}" == "1" ]]; then EXTRA_FLAGS=(-D HANDOFF_WATCHER_QA); fi
xcrun swiftc "${EXTRA_FLAGS[@]}" -swift-version 5 -O -target arm64-apple-macos27.0 -module-cache-path "$BUILD_DIR/module-cache" "$PROJECT_DIR/Sources/Localization.swift" "$PROJECT_DIR/Sources/Services.swift" "$PROJECT_DIR/Sources/Artwork.swift" "$PROJECT_DIR/Sources/App.swift" -o "$APP_DIR/Contents/MacOS/HandoffWatcher"
xcrun swiftc -swift-version 5 -O -module-cache-path "$BUILD_DIR/module-cache" "$PROJECT_DIR/Sources/Artwork.swift" "$PROJECT_DIR/Resources/GenerateIcons.swift" -o "$BUILD_DIR/generate-icons"
"$BUILD_DIR/generate-icons" "$BUILD_DIR/HandoffWatcher.iconset" "$APP_DIR/Contents/Resources/HandoffWatcher.icns"
cp "$PROJECT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
if [[ "${HANDOFF_WATCHER_QA:-0}" == "1" ]]; then
    /usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier local.handoffwatcher.preview' "$APP_DIR/Contents/Info.plist"
fi
for language in en zh-Hans; do
    ditto "$PROJECT_DIR/Resources/$language.lproj" "$APP_DIR/Contents/Resources/$language.lproj"
done
codesign --force --sign - "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"
# Package before copying into synced Documents: file providers may add FinderInfo there.
ditto --norsrc -c -k --keepParent "$APP_DIR" "$OUTPUT_DIR/HandoffWatcher-macOS27-arm64.zip"
ditto --norsrc "$APP_DIR" "$OUTPUT_DIR/HandoffWatcher.app"
xattr -dr com.apple.FinderInfo "$OUTPUT_DIR/HandoffWatcher.app" 2>/dev/null || true
echo "Built: $OUTPUT_DIR/HandoffWatcher.app"
echo "Packaged: $OUTPUT_DIR/HandoffWatcher-macOS27-arm64.zip"
