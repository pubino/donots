#!/bin/zsh
# Build, notarize, tag, and upload a new Donots release to GitHub.
# Interactive script with auto-detection of developer credentials.
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# Colors and formatting
# ─────────────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

info()    { echo "${BLUE}ℹ${RESET}  $1" }
success() { echo "${GREEN}✓${RESET}  $1" }
warn()    { echo "${YELLOW}⚠${RESET}  $1" }
error()   { echo "${RED}✗${RESET}  $1" >&2 }
step()    { echo "\n${MAGENTA}${BOLD}▶ $1${RESET}" }
prompt()  { echo -n "${CYAN}?${RESET}  $1" }

# ─────────────────────────────────────────────────────────────────────────────
# Paths
# ─────────────────────────────────────────────────────────────────────────────
SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR}/.."
BUILD_DIR="${PROJECT_DIR}/.build/release"
APP_PATH="${BUILD_DIR}/Donots.app"
ENTITLEMENTS="${PROJECT_DIR}/Resources/Donots.entitlements"
PLIST="${PROJECT_DIR}/Resources/Info.plist"

# ─────────────────────────────────────────────────────────────────────────────
# Header
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "${BOLD}${MAGENTA}╔════════════════════════════════════════════════════════════╗${RESET}"
echo "${BOLD}${MAGENTA}║${RESET}                ${BOLD}Donots Release Tool${RESET}                       ${BOLD}${MAGENTA}║${RESET}"
echo "${BOLD}${MAGENTA}╚════════════════════════════════════════════════════════════╝${RESET}"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# Parse arguments
# ─────────────────────────────────────────────────────────────────────────────
SKIP_NOTARIZE=false
VERSION=""
for arg in "$@"; do
    case "$arg" in
        --skip-notarize) SKIP_NOTARIZE=true ;;
        -h|--help)
            echo "Usage: ${BOLD}$0${RESET} [options] [version]"
            echo ""
            echo "Options:"
            echo "  ${CYAN}--skip-notarize${RESET}  Skip code signing and notarization"
            echo "  ${CYAN}-h, --help${RESET}       Show this help message"
            echo ""
            echo "If version is not provided, you will be prompted interactively."
            exit 0
            ;;
        *) VERSION="$arg" ;;
    esac
done

# ─────────────────────────────────────────────────────────────────────────────
# Get current version and prompt for new version
# ─────────────────────────────────────────────────────────────────────────────
CURRENT_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PLIST" 2>/dev/null || echo "1.0.0")
info "Current version: ${BOLD}${CURRENT_VERSION}${RESET}"

# Suggest next version (increment patch)
if [[ "$CURRENT_VERSION" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    SUGGESTED_VERSION="${match[1]}.${match[2]}.$((${match[3]} + 1))"
else
    SUGGESTED_VERSION="1.0.0"
fi

if [[ -z "$VERSION" ]]; then
    prompt "Enter new version [${SUGGESTED_VERSION}]: "
    read -r VERSION
    VERSION="${VERSION:-$SUGGESTED_VERSION}"
fi

# Validate version format
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    error "Invalid version format: ${VERSION}"
    info "Expected format: X.Y.Z (e.g., 1.2.0)"
    exit 1
fi

TAG="v${VERSION}"
ZIP_NAME="Donots-${VERSION}.zip"
ZIP_PATH="${BUILD_DIR}/${ZIP_NAME}"

# Check if tag already exists
if git tag -l "$TAG" 2>/dev/null | grep -q "$TAG"; then
    warn "Tag ${BOLD}${TAG}${RESET} already exists"
    prompt "Continue anyway? [y/N]: "
    read -r continue_anyway
    if [[ ! "$continue_anyway" =~ ^[Yy]$ ]]; then
        info "Aborted"
        exit 0
    fi
fi

success "Releasing version: ${BOLD}${VERSION}${RESET}"

# ─────────────────────────────────────────────────────────────────────────────
# Notarization setup (if not skipping)
# ─────────────────────────────────────────────────────────────────────────────
KEYCHAIN_PROFILE=""
USE_KEYCHAIN=false
DO_NOTARIZE=true

if [[ "$SKIP_NOTARIZE" == true ]]; then
    DO_NOTARIZE=false
    info "Notarization skipped via --skip-notarize flag"
else
    # Check if app is already notarized and stapled
    if [[ -d "$APP_PATH" ]]; then
        if xcrun stapler validate "$APP_PATH" 2>/dev/null; then
            success "App is already notarized and stapled"
            prompt "Re-notarize anyway? [y/N]: "
            read -r renotarize
            if [[ ! "$renotarize" =~ ^[Yy]$ ]]; then
                DO_NOTARIZE=false
                info "Skipping notarization (already complete)"
            fi
        fi
    fi
fi

if [[ "$DO_NOTARIZE" == true ]]; then
    step "Setting up code signing..."

    # Auto-detect Developer ID from keychain
    DETECTED_IDENTITIES=()
    while IFS= read -r line; do
        if [[ "$line" =~ '"Developer ID Application: (.+)"' ]]; then
            DETECTED_IDENTITIES+=("${match[1]}")
        fi
    done < <(security find-identity -v -p codesigning 2>/dev/null)

    if [[ ${#DETECTED_IDENTITIES[@]} -eq 0 ]]; then
        warn "No Developer ID Application certificates found"
        prompt "Skip notarization? [Y/n]: "
        read -r skip_nota
        if [[ "$skip_nota" =~ ^[Nn]$ ]]; then
            error "Cannot proceed without a Developer ID certificate"
            exit 1
        fi
        DO_NOTARIZE=false
    else
        if [[ -n "${DEVELOPER_ID:-}" ]]; then
            success "Using DEVELOPER_ID from environment: ${BOLD}$DEVELOPER_ID${RESET}"
        elif [[ ${#DETECTED_IDENTITIES[@]} -eq 1 ]]; then
            DEVELOPER_ID="${DETECTED_IDENTITIES[1]}"
            success "Auto-detected: ${BOLD}$DEVELOPER_ID${RESET}"
        else
            info "Multiple identities found:"
            for i in {1..${#DETECTED_IDENTITIES[@]}}; do
                echo "    ${CYAN}$i)${RESET} ${DETECTED_IDENTITIES[$i]}"
            done
            prompt "Select identity [1-${#DETECTED_IDENTITIES[@]}]: "
            read -r selection
            if [[ ! "$selection" =~ ^[0-9]+$ ]] || (( selection < 1 || selection > ${#DETECTED_IDENTITIES[@]} )); then
                error "Invalid selection"
                exit 1
            fi
            DEVELOPER_ID="${DETECTED_IDENTITIES[$selection]}"
            success "Selected: ${BOLD}$DEVELOPER_ID${RESET}"
        fi

        # Extract Team ID from Developer ID
        if [[ -n "${TEAM_ID:-}" ]]; then
            success "Using TEAM_ID from environment: ${BOLD}$TEAM_ID${RESET}"
        elif [[ "$DEVELOPER_ID" =~ '\(([A-Z0-9]+)\)$' ]]; then
            TEAM_ID="${match[1]}"
            success "Extracted Team ID: ${BOLD}$TEAM_ID${RESET}"
        else
            prompt "Enter your Apple Developer Team ID: "
            read -r TEAM_ID
            [[ -z "$TEAM_ID" ]] && { error "Team ID is required"; exit 1; }
        fi

        # Check for keychain credentials
        step "Checking notarization credentials..."
        
        if xcrun notarytool history --keychain-profile "Donots" 2>/dev/null | head -1 | grep -q "Successfully"; then
            KEYCHAIN_PROFILE="Donots"
            USE_KEYCHAIN=true
            success "Found stored keychain profile: ${BOLD}Donots${RESET}"
        elif xcrun notarytool history --keychain-profile "notarytool" 2>/dev/null | head -1 | grep -q "Successfully"; then
            KEYCHAIN_PROFILE="notarytool"
            USE_KEYCHAIN=true
            success "Found stored keychain profile: ${BOLD}notarytool${RESET}"
        elif [[ -n "${APPLE_ID:-}" && -n "${APP_PASSWORD:-}" ]]; then
            success "Using credentials from environment variables"
        else
            warn "No stored keychain profile found"
            info "You can store credentials with:"
            echo "    ${DIM}xcrun notarytool store-credentials \"Donots\" \\${RESET}"
            echo "    ${DIM}  --apple-id \"your@email.com\" \\${RESET}"
            echo "    ${DIM}  --team-id \"$TEAM_ID\" \\${RESET}"
            echo "    ${DIM}  --password \"app-specific-password\"${RESET}"
            echo ""
            
            prompt "Enter your Apple ID email: "
            read -r APPLE_ID
            [[ -z "$APPLE_ID" ]] && { error "Apple ID is required"; exit 1; }
            
            prompt "Enter app-specific password: "
            read -rs APP_PASSWORD
            echo ""
            [[ -z "$APP_PASSWORD" ]] && { error "App password is required"; exit 1; }

            # Offer to save credentials
            prompt "Save credentials to keychain for future use? [y/N]: "
            read -r save_creds
            if [[ "$save_creds" =~ ^[Yy]$ ]]; then
                if xcrun notarytool store-credentials "Donots" \
                    --apple-id "$APPLE_ID" \
                    --team-id "$TEAM_ID" \
                    --password "$APP_PASSWORD" 2>/dev/null; then
                    success "Credentials saved to keychain as ${BOLD}Donots${RESET}"
                    KEYCHAIN_PROFILE="Donots"
                    USE_KEYCHAIN=true
                else
                    warn "Failed to save credentials (continuing anyway)"
                fi
            fi
        fi
    fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# Summary and confirmation
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "${BOLD}Release Configuration:${RESET}"
echo "    ${DIM}Version:${RESET}      ${VERSION} → ${TAG}"
echo "    ${DIM}App:${RESET}          ${APP_PATH}"
echo "    ${DIM}ZIP:${RESET}          ${ZIP_NAME}"
if [[ "$DO_NOTARIZE" == true ]]; then
    echo "    ${DIM}Developer:${RESET}    ${DEVELOPER_ID}"
    echo "    ${DIM}Notarize:${RESET}     ${GREEN}Yes${RESET}"
else
    echo "    ${DIM}Notarize:${RESET}     ${YELLOW}Skipped${RESET}"
fi
echo ""

prompt "Proceed with release? [Y/n]: "
read -r proceed
if [[ "$proceed" =~ ^[Nn]$ ]]; then
    info "Aborted"
    exit 0
fi

# ─────────────────────────────────────────────────────────────────────────────
# Step 1: Update version in Info.plist
# ─────────────────────────────────────────────────────────────────────────────
step "Updating Info.plist..."

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "$PLIST"
success "Version set to ${VERSION}"

# ─────────────────────────────────────────────────────────────────────────────
# Step 2: Build
# ─────────────────────────────────────────────────────────────────────────────
step "Building release..."

cd "$PROJECT_DIR"
swift build -c release
success "Build complete"

# ─────────────────────────────────────────────────────────────────────────────
# Step 3: Assemble .app bundle
# ─────────────────────────────────────────────────────────────────────────────
step "Assembling Donots.app..."

APP_CONTENTS="${APP_PATH}/Contents"
rm -rf "$APP_PATH"
mkdir -p "${APP_CONTENTS}/MacOS"
mkdir -p "${APP_CONTENTS}/Resources"
cp "${BUILD_DIR}/Donots" "${APP_CONTENTS}/MacOS/Donots"
cp "${PLIST}" "${APP_CONTENTS}/Info.plist"
cp "${PROJECT_DIR}/Resources/Donots.entitlements" "${APP_CONTENTS}/Resources/Donots.entitlements"
cp "${PROJECT_DIR}/Resources/Donots.icns" "${APP_CONTENTS}/Resources/Donots.icns"
success "App bundle created"

# ─────────────────────────────────────────────────────────────────────────────
# Step 4: Notarize (if enabled)
# ─────────────────────────────────────────────────────────────────────────────
if [[ "$DO_NOTARIZE" == true ]]; then
    step "Codesigning..."
    
    codesign --force --options runtime \
        --entitlements "$ENTITLEMENTS" \
        --sign "Developer ID Application: ${DEVELOPER_ID}" \
        --timestamp \
        "$APP_PATH"
    
    if codesign --verify --deep --strict "$APP_PATH" 2>/dev/null; then
        success "Signature valid"
    else
        error "Signature verification failed"
        exit 1
    fi

    step "Creating ZIP for notarization..."
    
    rm -f "$ZIP_PATH"
    ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
    ZIP_SIZE=$(du -h "$ZIP_PATH" | cut -f1)
    success "Created ZIP ($ZIP_SIZE)"

    step "Submitting for notarization..."
    info "This may take a few minutes..."
    
    if [[ "$USE_KEYCHAIN" == true ]]; then
        xcrun notarytool submit "$ZIP_PATH" \
            --keychain-profile "$KEYCHAIN_PROFILE" \
            --wait
    else
        xcrun notarytool submit "$ZIP_PATH" \
            --apple-id "$APPLE_ID" \
            --password "$APP_PASSWORD" \
            --team-id "$TEAM_ID" \
            --wait
    fi
    success "Notarization approved"

    step "Stapling ticket..."
    
    xcrun stapler staple "$APP_PATH"
    success "Ticket stapled"

    # Re-zip after stapling
    step "Creating final ZIP..."
    
    rm -f "$ZIP_PATH"
    ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
    ZIP_SIZE=$(du -h "$ZIP_PATH" | cut -f1)
    success "Final ZIP created ($ZIP_SIZE)"
else
    step "Creating ZIP..."
    
    rm -f "$ZIP_PATH"
    ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
    ZIP_SIZE=$(du -h "$ZIP_PATH" | cut -f1)
    success "ZIP created ($ZIP_SIZE)"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Step 5: Git tag
# ─────────────────────────────────────────────────────────────────────────────
step "Creating Git tag..."

cd "$PROJECT_DIR/.."
git add -A

if git diff --cached --quiet; then
    info "No changes to commit"
else
    git commit -m "Release ${TAG}"
    success "Changes committed"
fi

if git tag -l "$TAG" | grep -q "$TAG"; then
    warn "Tag ${TAG} already exists, updating..."
    git tag -d "$TAG" 2>/dev/null || true
    git push origin ":refs/tags/$TAG" 2>/dev/null || true
fi

git tag -a "$TAG" -m "Donots ${TAG}"
success "Tag ${TAG} created"

step "Pushing to GitHub..."

git push origin main "$TAG"
success "Pushed to origin"

# ─────────────────────────────────────────────────────────────────────────────
# Step 6: Create GitHub release
# ─────────────────────────────────────────────────────────────────────────────
step "Creating GitHub release..."

# Check if release already exists
if gh release view "$TAG" &>/dev/null; then
    warn "Release ${TAG} already exists"
    prompt "Delete and recreate? [y/N]: "
    read -r recreate
    if [[ "$recreate" =~ ^[Yy]$ ]]; then
        gh release delete "$TAG" --yes
        success "Old release deleted"
    else
        info "Uploading asset to existing release..."
        gh release upload "$TAG" "$ZIP_PATH" --clobber
        success "Asset uploaded"
        
        echo ""
        echo "${GREEN}${BOLD}════════════════════════════════════════════════════════════${RESET}"
        echo "${GREEN}${BOLD}  ✓ Release ${TAG} updated!${RESET}"
        echo "${GREEN}${BOLD}════════════════════════════════════════════════════════════${RESET}"
        echo ""
        echo "  ${DIM}GitHub:${RESET}  https://github.com/pubino/donots/releases/tag/${TAG}"
        echo "  ${DIM}Pages:${RESET}   https://pubino.github.io/donots/"
        echo ""
        exit 0
    fi
fi

NOTARIZATION_NOTE=""
if [[ "$DO_NOTARIZE" == true ]]; then
    NOTARIZATION_NOTE="This release is signed and notarized by Apple."
else
    NOTARIZATION_NOTE="⚠️ This release is not notarized. You may need to right-click and select Open on first launch."
fi

gh release create "$TAG" "$ZIP_PATH" \
    --title "Donots ${TAG}" \
    --notes "## Donots ${TAG}

Download **${ZIP_NAME}**, unzip, and drag Donots.app to Applications.

${NOTARIZATION_NOTE}

Requires macOS 14 Sonoma or later."

success "GitHub release created"

# ─────────────────────────────────────────────────────────────────────────────
# Done!
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "${GREEN}${BOLD}════════════════════════════════════════════════════════════${RESET}"
echo "${GREEN}${BOLD}  ✓ Release ${TAG} complete!${RESET}"
echo "${GREEN}${BOLD}════════════════════════════════════════════════════════════${RESET}"
echo ""
echo "  ${DIM}GitHub:${RESET}  https://github.com/pubino/donots/releases/tag/${TAG}"
echo "  ${DIM}Pages:${RESET}   https://pubino.github.io/donots/"
echo ""
