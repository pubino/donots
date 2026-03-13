#!/bin/zsh
# Build Donots.app for Release
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR}/.."
BUILD_DIR="${PROJECT_DIR}/.build/release"
BUNDLE_ID="com.donots.app"

echo "Building Donots (Release)..."
cd "$PROJECT_DIR"

# Reset TCC privacy grants so permissions can be re-tested from scratch
echo "Resetting TCC permissions for ${BUNDLE_ID}..."
tccutil reset Accessibility "$BUNDLE_ID" 2>/dev/null || true
tccutil reset ScreenCapture "$BUNDLE_ID" 2>/dev/null || true
tccutil reset AppleEvents "$BUNDLE_ID" 2>/dev/null || true

# Remove old .app bundle to avoid stale icon/metadata caches
rm -rf "${BUILD_DIR}/Donots.app"

# Build with SwiftPM
swift build -c release

# Create .app bundle
APP_DIR="${BUILD_DIR}/Donots.app/Contents"
mkdir -p "${APP_DIR}/MacOS"
mkdir -p "${APP_DIR}/Resources"

# Copy binary
cp "${BUILD_DIR}/Donots" "${APP_DIR}/MacOS/Donots"

# Copy Info.plist
cp "${PROJECT_DIR}/Resources/Info.plist" "${APP_DIR}/Info.plist"

# Copy entitlements (for codesigning reference)
cp "${PROJECT_DIR}/Resources/Donots.entitlements" "${APP_DIR}/Resources/Donots.entitlements"

# Copy app icon
cp "${PROJECT_DIR}/Resources/Donots.icns" "${APP_DIR}/Resources/Donots.icns"

# Re-register with LaunchServices so macOS picks up the fresh icon
/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister -f "${BUILD_DIR}/Donots.app"

echo "Build complete: ${BUILD_DIR}/Donots.app"
