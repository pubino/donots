#!/bin/zsh
# Build, notarize, tag, and upload a new Donots release to GitHub.
# Usage: ./release.sh <version>   e.g. ./release.sh 1.2.0
# Requires: DEVELOPER_ID, TEAM_ID, APPLE_ID, APP_PASSWORD environment variables
# (skip notarization if these are unset by passing --skip-notarize)
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR}/.."
BUILD_DIR="${PROJECT_DIR}/.build/release"
APP_PATH="${BUILD_DIR}/Donots.app"
ENTITLEMENTS="${PROJECT_DIR}/Resources/Donots.entitlements"

# --- Parse arguments ---
SKIP_NOTARIZE=false
VERSION=""
for arg in "$@"; do
    case "$arg" in
        --skip-notarize) SKIP_NOTARIZE=true ;;
        *) VERSION="$arg" ;;
    esac
done

if [[ -z "$VERSION" ]]; then
    echo "Usage: $0 [--skip-notarize] <version>"
    echo "  e.g. $0 1.2.0"
    exit 1
fi

TAG="v${VERSION}"
ZIP_NAME="Donots-${VERSION}.zip"
ZIP_PATH="${BUILD_DIR}/${ZIP_NAME}"

echo "=== Donots Release ${TAG} ==="

# --- 1. Update version in Info.plist ---
echo "Updating Info.plist to version ${VERSION}..."
PLIST="${PROJECT_DIR}/Resources/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "$PLIST"

# --- 2. Build ---
echo "Building release..."
cd "$PROJECT_DIR"
swift build -c release

# --- 3. Create .app bundle ---
echo "Assembling Donots.app..."
APP_CONTENTS="${APP_PATH}/Contents"
mkdir -p "${APP_CONTENTS}/MacOS"
mkdir -p "${APP_CONTENTS}/Resources"
cp "${BUILD_DIR}/Donots" "${APP_CONTENTS}/MacOS/Donots"
cp "${PLIST}" "${APP_CONTENTS}/Info.plist"
cp "${PROJECT_DIR}/Resources/Donots.entitlements" "${APP_CONTENTS}/Resources/Donots.entitlements"
cp "${PROJECT_DIR}/Resources/Donots.icns" "${APP_CONTENTS}/Resources/Donots.icns"

# --- 4. Notarize (optional) ---
if [[ "$SKIP_NOTARIZE" == false ]]; then
    : "${DEVELOPER_ID:?Set DEVELOPER_ID to your Developer ID Application certificate name}"
    : "${TEAM_ID:?Set TEAM_ID to your Apple Developer Team ID}"
    : "${APPLE_ID:?Set APPLE_ID to your Apple ID email}"
    : "${APP_PASSWORD:?Set APP_PASSWORD to your app-specific password}"

    echo "Codesigning..."
    codesign --force --options runtime \
        --entitlements "$ENTITLEMENTS" \
        --sign "Developer ID Application: ${DEVELOPER_ID}" \
        --timestamp \
        "$APP_PATH"

    codesign --verify --deep --strict "$APP_PATH"

    echo "Creating ZIP for notarization..."
    ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

    echo "Submitting for notarization..."
    xcrun notarytool submit "$ZIP_PATH" \
        --apple-id "$APPLE_ID" \
        --password "$APP_PASSWORD" \
        --team-id "$TEAM_ID" \
        --wait

    echo "Stapling ticket..."
    xcrun stapler staple "$APP_PATH"

    # Re-zip after stapling
    rm -f "$ZIP_PATH"
    ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
else
    echo "Skipping notarization (--skip-notarize)."
    echo "Creating ZIP..."
    ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
fi

# --- 5. Git tag ---
echo "Tagging ${TAG}..."
cd "$PROJECT_DIR/.."
git add -A
git commit -m "Release ${TAG}" --allow-empty
git tag -a "$TAG" -m "Donots ${TAG}"
git push origin main "$TAG"

# --- 6. Create GitHub release ---
echo "Creating GitHub release..."
gh release create "$TAG" "$ZIP_PATH" \
    --title "Donots ${TAG}" \
    --notes "## Donots ${TAG}

Download **${ZIP_NAME}**, unzip, and drag Donots.app to Applications.

Requires macOS 14 Sonoma or later."

echo ""
echo "=== Release ${TAG} complete ==="
echo "  GitHub: https://github.com/pubino/donots/releases/tag/${TAG}"
echo "  Pages:  https://pubino.github.io/donots/"
