#!/bin/zsh
# Codesign and notarize Donots.app
# Interactive script with auto-detection of developer credentials
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
APP_PATH="${PROJECT_DIR}/.build/release/Donots.app"
ENTITLEMENTS="${PROJECT_DIR}/Resources/Donots.entitlements"
ZIP_PATH="${PROJECT_DIR}/.build/Donots.zip"

# ─────────────────────────────────────────────────────────────────────────────
# Header
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "${BOLD}${MAGENTA}╔════════════════════════════════════════════════════════════╗${RESET}"
echo "${BOLD}${MAGENTA}║${RESET}              ${BOLD}Donots Notarization Tool${RESET}                     ${BOLD}${MAGENTA}║${RESET}"
echo "${BOLD}${MAGENTA}╚════════════════════════════════════════════════════════════╝${RESET}"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# Check app exists
# ─────────────────────────────────────────────────────────────────────────────
if [[ ! -d "$APP_PATH" ]]; then
    error "App not found at ${DIM}$APP_PATH${RESET}"
    info "Run ${BOLD}./scripts/build.sh${RESET} first"
    exit 1
fi
success "Found app: ${DIM}$APP_PATH${RESET}"

# ─────────────────────────────────────────────────────────────────────────────
# Auto-detect Developer ID from keychain
# ─────────────────────────────────────────────────────────────────────────────
step "Detecting code signing identity..."

DETECTED_IDENTITIES=()
while IFS= read -r line; do
    if [[ "$line" =~ '"Developer ID Application: (.+)"' ]]; then
        DETECTED_IDENTITIES+=("${match[1]}")
    fi
done < <(security find-identity -v -p codesigning 2>/dev/null)

if [[ ${#DETECTED_IDENTITIES[@]} -eq 0 ]]; then
    error "No Developer ID Application certificates found in keychain"
    info "Install a Developer ID certificate from your Apple Developer account"
    exit 1
fi

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

# Extract Team ID from Developer ID (format: "Name (TEAMID)")
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

# ─────────────────────────────────────────────────────────────────────────────
# Check for stored keychain credentials or prompt
# ─────────────────────────────────────────────────────────────────────────────
step "Checking notarization credentials..."

KEYCHAIN_PROFILE=""
USE_KEYCHAIN=false

# Check for stored notarytool keychain profile
if xcrun notarytool history --keychain-profile "Donots" 2>/dev/null | head -1 | grep -q "Successfully"; then
    KEYCHAIN_PROFILE="Donots"
    USE_KEYCHAIN=true
    success "Found stored keychain profile: ${BOLD}Donots${RESET}"
elif xcrun notarytool history --keychain-profile "notarytool" 2>/dev/null | head -1 | grep -q "Successfully"; then
    KEYCHAIN_PROFILE="notarytool"
    USE_KEYCHAIN=true
    success "Found stored keychain profile: ${BOLD}notarytool${RESET}"
fi

if [[ "$USE_KEYCHAIN" == false ]]; then
    if [[ -n "${APPLE_ID:-}" && -n "${APP_PASSWORD:-}" ]]; then
        success "Using credentials from environment variables"
    else
        warn "No stored keychain profile found"
        info "You can store credentials with:"
        echo "    ${DIM}xcrun notarytool store-credentials \"Donots\" \\${RESET}"
        echo "    ${DIM}  --apple-id \"your@email.com\" \\${RESET}"
        echo "    ${DIM}  --team-id \"$TEAM_ID\" \\${RESET}"
        echo "    ${DIM}  --password \"app-specific-password\"${RESET}"
        echo ""
        
        if [[ -z "${APPLE_ID:-}" ]]; then
            prompt "Enter your Apple ID email: "
            read -r APPLE_ID
            [[ -z "$APPLE_ID" ]] && { error "Apple ID is required"; exit 1; }
        fi
        
        if [[ -z "${APP_PASSWORD:-}" ]]; then
            prompt "Enter app-specific password: "
            read -rs APP_PASSWORD
            echo ""
            [[ -z "$APP_PASSWORD" ]] && { error "App password is required"; exit 1; }
        fi

        # Offer to save credentials
        echo ""
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

# ─────────────────────────────────────────────────────────────────────────────
# Summary before proceeding
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "${BOLD}Configuration:${RESET}"
echo "    ${DIM}App:${RESET}          $APP_PATH"
echo "    ${DIM}Developer:${RESET}    $DEVELOPER_ID"
echo "    ${DIM}Team ID:${RESET}      $TEAM_ID"
if [[ "$USE_KEYCHAIN" == true ]]; then
    echo "    ${DIM}Credentials:${RESET}  Keychain profile '${KEYCHAIN_PROFILE}'"
else
    echo "    ${DIM}Credentials:${RESET}  $APPLE_ID"
fi
echo ""

prompt "Proceed with notarization? [Y/n]: "
read -r proceed
if [[ "$proceed" =~ ^[Nn]$ ]]; then
    info "Aborted"
    exit 0
fi

# ─────────────────────────────────────────────────────────────────────────────
# Codesign
# ─────────────────────────────────────────────────────────────────────────────
step "Codesigning app..."

codesign --force --options runtime \
    --entitlements "$ENTITLEMENTS" \
    --sign "Developer ID Application: ${DEVELOPER_ID}" \
    --timestamp \
    "$APP_PATH"

success "App signed"

step "Verifying signature..."
if codesign --verify --deep --strict "$APP_PATH" 2>/dev/null; then
    success "Signature valid"
else
    error "Signature verification failed"
    exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
# Create ZIP
# ─────────────────────────────────────────────────────────────────────────────
step "Creating ZIP archive..."

rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
ZIP_SIZE=$(du -h "$ZIP_PATH" | cut -f1)
success "Created ${DIM}$ZIP_PATH${RESET} ($ZIP_SIZE)"

# ─────────────────────────────────────────────────────────────────────────────
# Submit for notarization
# ─────────────────────────────────────────────────────────────────────────────
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

# ─────────────────────────────────────────────────────────────────────────────
# Staple
# ─────────────────────────────────────────────────────────────────────────────
step "Stapling notarization ticket..."

xcrun stapler staple "$APP_PATH"
success "Ticket stapled"

# ─────────────────────────────────────────────────────────────────────────────
# Done!
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "${GREEN}${BOLD}════════════════════════════════════════════════════════════${RESET}"
echo "${GREEN}${BOLD}  ✓ Notarization complete!${RESET}"
echo "${GREEN}${BOLD}════════════════════════════════════════════════════════════${RESET}"
echo ""
echo "  ${DIM}App:${RESET} $APP_PATH"
echo "  ${DIM}ZIP:${RESET} $ZIP_PATH"
echo ""
info "The app is now ready for distribution"
