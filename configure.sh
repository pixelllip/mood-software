#!/usr/bin/env bash
#
# configure.sh - XingHuo XueBan (ai_agent) Multi-Platform Configuration Tool
#
# Interactive shell script to modify version numbers, app names, package names,
# signing info, copyright, etc. across all platforms (Android/iOS/macOS/Windows/Linux/Web).
#
# Usage:
#   ./configure.sh                          # Interactive menu
#   ./configure.sh --set-version 2.0.0+1    # Non-interactive: set version
#   ./configure.sh --set-app-name "MyApp"   # Non-interactive: set app name
#

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ============================================================
# Color helpers
# ============================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
GRAY='\033[0;90m'
NC='\033[0m' # No Color

info()  { echo -e "${GREEN}  [OK]${NC} $1"; }
warn()  { echo -e "${YELLOW}  [WARN]${NC} $1"; }
skip()  { echo -e "${GRAY}  [SKIP]${NC} $1"; }
header(){ echo -e "${CYAN}$1${NC}"; }
label() { echo -e "${YELLOW}  $1${NC}"; }

# ============================================================
# Utility: sed in-place (works on both Linux and macOS)
# ============================================================
sed_inplace() {
    if [[ "$(uname)" == "Darwin" ]]; then
        sed -i '' "$@"
    else
        sed -i "$@"
    fi
}

# ============================================================
# Read current config from all platform files
# ============================================================
read_current_config() {
    # --- pubspec.yaml ---
    PUBSPEC="$ROOT_DIR/pubspec.yaml"
    VERSION=$(grep -m1 '^version:' "$PUBSPEC" | sed 's/^version:[[:space:]]*//' | tr -d '\r' || echo "N/A")

    # --- Android ---
    ANDROID_GRADLE="$ROOT_DIR/android/app/build.gradle.kts"
    ANDROID_APP_ID=$(grep -m1 'applicationId' "$ANDROID_GRADLE" | sed 's/.*applicationId\s*=\s*"\([^"]*\)".*/\1/' || echo "N/A")
    ANDROID_NS=$(grep -m1 'namespace' "$ANDROID_GRADLE" | sed 's/.*namespace\s*=\s*"\([^"]*\)".*/\1/' || echo "N/A")
    ANDROID_COMPILE_SDK=$(grep -m1 'compileSdk' "$ANDROID_GRADLE" | sed 's/.*compileSdk\s*=\s*\([^} ]*\).*/\1/' || echo "N/A")
    ANDROID_MIN_SDK=$(grep -m1 'minSdk' "$ANDROID_GRADLE" | sed 's/.*minSdk\s*=\s*\([^} ]*\).*/\1/' || echo "N/A")
    ANDROID_TARGET_SDK=$(grep -m1 'targetSdk' "$ANDROID_GRADLE" | sed 's/.*targetSdk\s*=\s*\([^} ]*\).*/\1/' || echo "N/A")

    if grep -q 'signingConfig.*getByName("release")' "$ANDROID_GRADLE" 2>/dev/null; then
        ANDROID_SIGNING="release (configured)"
    else
        ANDROID_SIGNING="debug (no release signing)"
    fi

    # --- iOS ---
    IOS_PLIST="$ROOT_DIR/ios/Runner/Info.plist"
    IOS_DISPLAY_NAME=$(grep -A1 'CFBundleDisplayName' "$IOS_PLIST" 2>/dev/null | grep '<string>' | sed 's/.*<string>\([^<]*\)<\/string>.*/\1/' || echo "N/A")

    # --- macOS ---
    MAC_APPINFO="$ROOT_DIR/macos/Runner/Configs/AppInfo.xcconfig"
    MAC_PRODUCT_NAME=$(grep -m1 '^PRODUCT_NAME' "$MAC_APPINFO" 2>/dev/null | sed 's/^PRODUCT_NAME[[:space:]]*=[[:space:]]*//' || echo "N/A")
    MAC_BUNDLE_ID=$(grep -m1 '^PRODUCT_BUNDLE_IDENTIFIER' "$MAC_APPINFO" 2>/dev/null | sed 's/^PRODUCT_BUNDLE_IDENTIFIER[[:space:]]*=[[:space:]]*//' || echo "N/A")
    MAC_COPYRIGHT=$(grep -m1 '^PRODUCT_COPYRIGHT' "$MAC_APPINFO" 2>/dev/null | sed 's/^PRODUCT_COPYRIGHT[[:space:]]*=[[:space:]]*//' || echo "N/A")

    # --- Windows ---
    WIN_RC="$ROOT_DIR/windows/runner/Runner.rc"
    WIN_COMPANY=$(grep -m1 'CompanyName' "$WIN_RC" 2>/dev/null | sed 's/.*"\([^"]*\)".*/\1/' || echo "N/A")
    WIN_FILE_DESC=$(grep -m1 'FileDescription' "$WIN_RC" 2>/dev/null | sed 's/.*"\([^"]*\)".*/\1/' || echo "N/A")
    WIN_PRODUCT=$(grep -m1 '"ProductName"' "$WIN_RC" 2>/dev/null | sed 's/.*"\([^"]*\)".*/\1/' || echo "N/A")
    WIN_ORIG_NAME=$(grep -m1 'OriginalFilename' "$WIN_RC" 2>/dev/null | sed 's/.*"\([^"]*\)".*/\1/' || echo "N/A")
    WIN_COPYRIGHT=$(grep -m1 'LegalCopyright' "$WIN_RC" 2>/dev/null | sed 's/.*"\([^"]*\)".*/\1/' || echo "N/A")

    # --- Linux ---
    LINUX_CMAKE="$ROOT_DIR/linux/CMakeLists.txt"
    LINUX_APP_ID=$(grep -m1 'APPLICATION_ID' "$LINUX_CMAKE" 2>/dev/null | sed 's/.*"\([^"]*\)".*/\1/' || echo "N/A")
    LINUX_BIN_NAME=$(grep -m1 'BINARY_NAME' "$LINUX_CMAKE" 2>/dev/null | sed 's/.*set(BINARY_NAME[[:space:]]*"\([^"]*\)".*/\1/' || echo "N/A")

    # --- Web ---
    WEB_MANIFEST="$ROOT_DIR/web/manifest.json"
    WEB_NAME=$(grep -m1 '"name"' "$WEB_MANIFEST" 2>/dev/null | sed 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' || echo "N/A")
    WEB_SHORT_NAME=$(grep -m1 '"short_name"' "$WEB_MANIFEST" 2>/dev/null | sed 's/.*"short_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' || echo "N/A")
    WEB_DESC=$(grep -m1 '"description"' "$WEB_MANIFEST" 2>/dev/null | sed 's/.*"description"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' || echo "N/A")
    WEB_TITLE=$(grep -m1 '<title>' "$ROOT_DIR/web/index.html" 2>/dev/null | sed 's/.*<title>\([^<]*\)<\/title>.*/\1/' || echo "N/A")
}

# ============================================================
# Display current config
# ============================================================
show_current_config() {
    echo ""
    header "=================================================="
    header "  CURRENT CONFIG OVERVIEW"
    header "=================================================="

    echo ""
    label "[Version]"
    echo "    App version:          ${VERSION}"

    echo ""
    label "[Android]"
    echo "    applicationId:        ${ANDROID_APP_ID}"
    echo "    namespace:            ${ANDROID_NS}"
    echo "    compileSdk:           ${ANDROID_COMPILE_SDK}"
    echo "    minSdk:               ${ANDROID_MIN_SDK}"
    echo "    targetSdk:            ${ANDROID_TARGET_SDK}"
    echo "    signing:              ${ANDROID_SIGNING}"

    echo ""
    label "[iOS]"
    echo "    DisplayName:          ${IOS_DISPLAY_NAME}"

    echo ""
    label "[macOS]"
    echo "    PRODUCT_NAME:         ${MAC_PRODUCT_NAME}"
    echo "    Bundle ID:            ${MAC_BUNDLE_ID}"
    echo "    Copyright:            ${MAC_COPYRIGHT}"

    echo ""
    label "[Windows]"
    echo "    CompanyName:          ${WIN_COMPANY}"
    echo "    FileDescription:      ${WIN_FILE_DESC}"
    echo "    ProductName:          ${WIN_PRODUCT}"
    echo "    OriginalFilename:     ${WIN_ORIG_NAME}"
    echo "    LegalCopyright:       ${WIN_COPYRIGHT}"

    echo ""
    label "[Linux]"
    echo "    APPLICATION_ID:       ${LINUX_APP_ID}"
    echo "    BINARY_NAME:          ${LINUX_BIN_NAME}"

    echo ""
    label "[Web]"
    echo "    name:                 ${WEB_NAME}"
    echo "    short_name:           ${WEB_SHORT_NAME}"
    echo "    description:          ${WEB_DESC}"
    echo "    title:                ${WEB_TITLE}"
    echo ""
}

# ============================================================
# File update helper (sed-based)
# ============================================================


# ============================================================
# Platform modification functions
# ============================================================

set_app_version() {
    echo ""
    label "--- Set Version ---"
    echo "Current version: ${VERSION}"
    read -r -p "Enter new version (format: x.y.z+build, empty to skip): " new_version
    if [[ -z "$new_version" ]]; then
        skip "No input, skipped"
        return
    fi
    sed_inplace "s/^version:[[:space:]]*\(.*\)/version: ${new_version}/" "$PUBSPEC"
    VERSION="$new_version"
}

set_android_config() {
    echo ""
    label "--- Android Config ---"

    echo "Current applicationId: ${ANDROID_APP_ID}"
    read -r -p "New applicationId (empty to skip): " new_id
    if [[ -n "$new_id" ]]; then
        sed_inplace "s/\(applicationId\s*=\s*\"\)[^\"]*\(\"\)/\1${new_id}\2/" "$ANDROID_GRADLE"
        info "applicationId updated"
        ANDROID_APP_ID="$new_id"
    fi

    echo "Current namespace: ${ANDROID_NS}"
    read -r -p "New namespace (empty to skip): " new_ns
    if [[ -n "$new_ns" ]]; then
        sed_inplace "s/\(namespace\s*=\s*\"\)[^\"]*\(\"\)/\1${new_ns}\2/" "$ANDROID_GRADLE"
        info "namespace updated"
        ANDROID_NS="$new_ns"
    fi

    echo "Current compileSdk=${ANDROID_COMPILE_SDK}, minSdk=${ANDROID_MIN_SDK}, targetSdk=${ANDROID_TARGET_SDK}"
    read -r -p "compileSdk (empty to keep): " new_c
    read -r -p "minSdk (empty to keep): " new_m
    read -r -p "targetSdk (empty to keep): " new_t
    if [[ -n "$new_c" ]]; then
        sed_inplace "s/\(compileSdk\s*=\s*\)[^} ]*/\1${new_c}/" "$ANDROID_GRADLE"
        ANDROID_COMPILE_SDK="$new_c"
    fi
    if [[ -n "$new_m" ]]; then
        sed_inplace "s/\(minSdk\s*=\s*\)[^} ]*/\1${new_m}/" "$ANDROID_GRADLE"
        ANDROID_MIN_SDK="$new_m"
    fi
    if [[ -n "$new_t" ]]; then
        sed_inplace "s/\(targetSdk\s*=\s*\)[^} ]*/\1${new_t}/" "$ANDROID_GRADLE"
        ANDROID_TARGET_SDK="$new_t"
    fi
}

set_android_signing() {
    echo ""
    label "--- Android Signing Config ---"
    echo "This will configure release signing. You need a .jks or .keystore file ready."

    read -r -p "Configure release signing? (y/n, default n): " setup_sign
    if [[ "$setup_sign" != "y" ]]; then
        skip "Signing config skipped"
        return
    fi

    read -r -p "Keystore file path (relative to android/app/, e.g. my-release-key.jks): " keystore_path
    if [[ -z "$keystore_path" ]]; then
        skip "No path entered"
        return
    fi
    read -r -p "storePassword: " store_password
    read -r -p "keyAlias: " key_alias
    read -r -p "keyPassword: " key_password

    if grep -q 'signingConfigs' "$ANDROID_GRADLE" 2>/dev/null; then
        warn "signingConfigs already exists, please manually edit $ANDROID_GRADLE"
    else
        cat >> "$ANDROID_GRADLE" << EOF

android {
    signingConfigs {
        release {
            storeFile = file("${keystore_path}")
            storePassword = "${store_password}"
            keyAlias = "${key_alias}"
            keyPassword = "${key_password}"
        }
    }
    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}
EOF
        info "Release signing config written"

        # Generate key.properties for CI/CD
        cat > "$ROOT_DIR/android/key.properties" << EOF
storePassword=${store_password}
keyPassword=${key_password}
keyAlias=${key_alias}
storeFile=${keystore_path}
EOF
        info "android/key.properties generated"
    fi
}

set_ios_display_name() {
    echo ""
    label "--- iOS Display Name ---"
    echo "Current CFBundleDisplayName: ${IOS_DISPLAY_NAME}"
    read -r -p "New display name (empty to skip): " new_name
    if [[ -n "$new_name" ]]; then
        perl -i -0777pe "s|(<key>CFBundleDisplayName</key>\s*<string>)[^<]*(</string>)|\${1}${new_name}\${2}|" "$IOS_PLIST"
        info "iOS display name updated"
        IOS_DISPLAY_NAME="$new_name"
    fi
}

set_macos_config() {
    echo ""
    label "--- macOS Config ---"

    echo "Current PRODUCT_NAME: ${MAC_PRODUCT_NAME}"
    read -r -p "New PRODUCT_NAME (empty to skip): " new_name
    if [[ -n "$new_name" ]]; then
        sed_inplace "s/^PRODUCT_NAME[[:space:]]*=.*/PRODUCT_NAME = ${new_name}/" "$MAC_APPINFO"
        info "macOS PRODUCT_NAME updated"
        MAC_PRODUCT_NAME="$new_name"
    fi

    echo "Current PRODUCT_BUNDLE_IDENTIFIER: ${MAC_BUNDLE_ID}"
    read -r -p "New Bundle ID (empty to skip): " new_bundle
    if [[ -n "$new_bundle" ]]; then
        sed_inplace "s/^PRODUCT_BUNDLE_IDENTIFIER[[:space:]]*=.*/PRODUCT_BUNDLE_IDENTIFIER = ${new_bundle}/" "$MAC_APPINFO"
        info "macOS Bundle ID updated"
        MAC_BUNDLE_ID="$new_bundle"
    fi

    echo "Current PRODUCT_COPYRIGHT: ${MAC_COPYRIGHT}"
    read -r -p "New copyright (empty to skip): " new_copyright
    if [[ -n "$new_copyright" ]]; then
        sed_inplace "s/^PRODUCT_COPYRIGHT[[:space:]]*=.*/PRODUCT_COPYRIGHT = ${new_copyright}/" "$MAC_APPINFO"
        info "macOS copyright updated"
        MAC_COPYRIGHT="$new_copyright"
    fi
}

set_windows_config() {
    echo ""
    label "--- Windows Config ---"

    local fields=(
        "CompanyName:${WIN_COMPANY}"
        "FileDescription:${WIN_FILE_DESC}"
        "ProductName:${WIN_PRODUCT}"
        "OriginalFilename:${WIN_ORIG_NAME}"
        "LegalCopyright:${WIN_COPYRIGHT}"
    )

    local content
    content=$(cat "$WIN_RC")

    for field_entry in "${fields[@]}"; do
        local name="${field_entry%%:*}"
        local current_val="${field_entry#*:}"
        echo "Current ${name}: ${current_val}"
        read -r -p "New value (empty to skip): " new_val
        if [[ -n "$new_val" ]]; then
            sed_inplace "s/\(\"${name}\",[[:space:]]*\"\)[^\"]*\(\"\)/\1${new_val}\2/" "$WIN_RC"
            info "${name} updated"
        fi
    done
}

set_linux_config() {
    echo ""
    label "--- Linux Config ---"

    echo "Current APPLICATION_ID: ${LINUX_APP_ID}"
    read -r -p "New APPLICATION_ID (e.g. com.example.myapp, empty to skip): " new_id
    if [[ -n "$new_id" ]]; then
        sed_inplace "s/\(set(APPLICATION_ID[[:space:]]*\"\)[^\"]*\(\"\)/\1${new_id}\2/" "$LINUX_CMAKE"
        info "Linux APPLICATION_ID updated"
        LINUX_APP_ID="$new_id"
    fi

    echo "Current BINARY_NAME: ${LINUX_BIN_NAME}"
    read -r -p "New BINARY_NAME (empty to skip): " new_bin
    if [[ -n "$new_bin" ]]; then
        sed_inplace "s/\(set(BINARY_NAME[[:space:]]*\"\)[^\"]*\(\"\)/\1${new_bin}\2/" "$LINUX_CMAKE"
        info "Linux BINARY_NAME updated"
        LINUX_BIN_NAME="$new_bin"
    fi
}

set_web_config() {
    echo ""
    label "--- Web Config ---"

    echo "Current name: ${WEB_NAME}"
    read -r -p "New name (empty to skip): " new_name
    if [[ -n "$new_name" ]]; then
        sed_inplace "s/\(\"name\"[[:space:]]*:[[:space:]]*\"\)[^\"]*\(\"\)/\1${new_name}\2/" "$WEB_MANIFEST"
        WEB_NAME="$new_name"
    fi

    echo "Current short_name: ${WEB_SHORT_NAME}"
    read -r -p "New short_name (empty to skip): " new_short
    if [[ -n "$new_short" ]]; then
        sed_inplace "s/\(\"short_name\"[[:space:]]*:[[:space:]]*\"\)[^\"]*\(\"\)/\1${new_short}\2/" "$WEB_MANIFEST"
        WEB_SHORT_NAME="$new_short"
    fi

    echo "Current description: ${WEB_DESC}"
    read -r -p "New description (empty to skip): " new_desc
    if [[ -n "$new_desc" ]]; then
        sed_inplace "s/\(\"description\"[[:space:]]*:[[:space:]]*\"\)[^\"]*\(\"\)/\1${new_desc}\2/" "$WEB_MANIFEST"
        WEB_DESC="$new_desc"
    fi

    info "web/manifest.json updated"

    echo "Current title: ${WEB_TITLE}"
    read -r -p "New title (empty to skip): " new_title
    if [[ -n "$new_title" ]]; then
        sed_inplace "s|<title>[^<]*</title>|<title>${new_title}</title>|" "$ROOT_DIR/web/index.html"
        info "web/index.html title updated"
        WEB_TITLE="$new_title"
    fi
}

set_ios_bundle_id() {
    echo ""
    label "--- iOS Bundle ID ---"
    local current_bundle
    current_bundle=$(grep -A1 'CFBundleIdentifier' "$IOS_PLIST" 2>/dev/null | grep '<string>' | sed 's/.*<string>\([^<]*\)<\/string>.*/\1/' || echo "N/A")
    echo "Current CFBundleIdentifier: ${current_bundle}"
    read -r -p "New Bundle ID (empty to skip): " new_bundle
    if [[ -n "$new_bundle" ]]; then
        perl -i -0777pe "s|(<key>CFBundleIdentifier</key>\s*<string>)[^<]*(</string>)|\${1}${new_bundle}\${2}|" "$IOS_PLIST"
        info "iOS CFBundleIdentifier updated"
    fi
}

set_app_name() {
    echo ""
    label "--- Set App Name (All Platforms) ---"
    echo "Current names:"
    echo "  iOS display name:         ${IOS_DISPLAY_NAME}"
    echo "  macOS PRODUCT_NAME:       ${MAC_PRODUCT_NAME}"
    echo "  Windows ProductName:      ${WIN_PRODUCT}"
    echo "  Web name:                 ${WEB_NAME}"
    echo "  Web title:                ${WEB_TITLE}"

    echo ""
    read -r -p "Enter new app name (empty to skip): " new_name
    if [[ -z "$new_name" ]]; then
        skip "Skipped"
        return
    fi

    # iOS
    perl -i -0777pe "s|(<key>CFBundleDisplayName</key>\s*<string>)[^<]*(</string>)|\${1}${new_name}\${2}|" "$IOS_PLIST"
    info "iOS CFBundleDisplayName updated"
    IOS_DISPLAY_NAME="$new_name"

    # macOS
    sed_inplace "s/^PRODUCT_NAME[[:space:]]*=.*/PRODUCT_NAME = ${new_name}/" "$MAC_APPINFO"
    info "macOS PRODUCT_NAME updated"
    MAC_PRODUCT_NAME="$new_name"

    # Windows
    sed_inplace "s/\(\"ProductName\",[[:space:]]*\"\)[^\"]*\(\"\)/\1${new_name}\2/" "$WIN_RC"
    info "Windows ProductName updated"
    WIN_PRODUCT="$new_name"

    # Web manifest
    sed_inplace "s/\(\"name\"[[:space:]]*:[[:space:]]*\"\)[^\"]*\(\"\)/\1${new_name}\2/" "$WEB_MANIFEST"
    sed_inplace "s/\(\"short_name\"[[:space:]]*:[[:space:]]*\"\)[^\"]*\(\"\)/\1${new_name}\2/" "$WEB_MANIFEST"
    info "Web manifest name/short_name updated"

    # Web title
    sed_inplace "s|<title>[^<]*</title>|<title>${new_name}</title>|" "$ROOT_DIR/web/index.html"
    info "Web title updated"

    WEB_NAME="$new_name"
    WEB_SHORT_NAME="$new_name"
    WEB_TITLE="$new_name"

    echo ""
    info "App name updated to: ${new_name}"
}

set_backend_version() {
    echo ""
    label "--- Backend (Kotlin) Version ---"
    local kotlin_file="$ROOT_DIR/backend_kotlin/build.gradle.kts"
    local current_ver
    current_ver=$(grep -m1 'version' "$kotlin_file" 2>/dev/null | sed 's/.*version\s*=\s*"\([^"]*\)".*/\1/' || echo "")
    if [[ -n "$current_ver" ]]; then
        echo "Current version: ${current_ver}"
    else
        echo "Current: no version field set"
    fi

    read -r -p "New version (empty to skip): " new_ver
    if [[ -n "$new_ver" ]]; then
        if grep -q 'version\s*=' "$kotlin_file" 2>/dev/null; then
            sed_inplace "s/\(version\s*=\s*\"\)[^\"]*\(\"\)/\1${new_ver}\2/" "$kotlin_file"
        else
            # Insert version after first line
            sed_inplace "1s/^/version = \"${new_ver}\"\n/" "$kotlin_file"
        fi
        info "Backend version updated to ${new_ver}"
    fi
}

# ============================================================
# Main menu
# ============================================================
show_menu() {
    clear 2>/dev/null || true
    header "=================================================="
    header "  XingHuo XueBan - Multi-Platform Config Tool"
    header "=================================================="

    read_current_config
    show_current_config

    header "=================================================="
    header "  Select option to modify:"
    header "=================================================="
    echo "  1)  Version (pubspec.yaml)"
    echo "  2)  App Name (all platforms)"
    echo "  3)  Android (appId/namespace/SDK)"
    echo "  4)  Android signing (release keystore)"
    echo "  5)  iOS display name"
    echo "  6)  iOS Bundle ID"
    echo "  7)  macOS (name/Bundle ID/copyright)"
    echo "  8)  Windows (company/product/copyright/file)"
    echo "  9)  Linux (APPLICATION_ID/BINARY_NAME)"
    echo "  10) Web (name/description/title)"
    echo "  11) Backend Kotlin version"
    echo "  12) iOS signing (open Xcode)"
    echo "  q)  Quit"
    echo ""
}

# ============================================================
# Parse command line arguments
# ============================================================
SET_VERSION=""
SET_APP_NAME=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --set-version)
            SET_VERSION="$2"
            shift 2
            ;;
        --set-app-name)
            SET_APP_NAME="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--set-version x.y.z+build] [--set-app-name \"Name\"]"
            exit 1
            ;;
    esac
done

# ============================================================
# Non-interactive mode
# ============================================================
if [[ -n "$SET_VERSION" || -n "$SET_APP_NAME" ]]; then
    read_current_config

    if [[ -n "$SET_VERSION" ]]; then
        sed_inplace "s/^version:[[:space:]]*\(.*\)/version: ${SET_VERSION}/" "$PUBSPEC"
    fi
    if [[ -n "$SET_APP_NAME" ]]; then
        perl -i -0777pe "s|(<key>CFBundleDisplayName</key>\s*<string>)[^<]*(</string>)|\${1}${SET_APP_NAME}\${2}|" "$IOS_PLIST"
        info "iOS CFBundleDisplayName updated"

        sed_inplace "s/^PRODUCT_NAME[[:space:]]*=.*/PRODUCT_NAME = ${SET_APP_NAME}/" "$MAC_APPINFO"
        info "macOS PRODUCT_NAME updated"

        sed_inplace "s/\(\"ProductName\",[[:space:]]*\"\)[^\"]*\(\"\)/\1${SET_APP_NAME}\2/" "$WIN_RC"
        info "Windows ProductName updated"

        sed_inplace "s/\(\"name\"[[:space:]]*:[[:space:]]*\"\)[^\"]*\(\"\)/\1${SET_APP_NAME}\2/" "$WEB_MANIFEST"
        sed_inplace "s/\(\"short_name\"[[:space:]]*:[[:space:]]*\"\)[^\"]*\(\"\)/\1${SET_APP_NAME}\2/" "$WEB_MANIFEST"
        info "Web manifest name/short_name updated"

        sed_inplace "s|<title>[^<]*</title>|<title>${SET_APP_NAME}</title>|" "$ROOT_DIR/web/index.html"
        info "Web title updated"
    fi
    exit 0
fi

# ============================================================
# Interactive mode
# ============================================================
while true; do
    show_menu
    read -r -p "Enter option: " choice
    case "$choice" in
        1)  set_app_version ;;
        2)  set_app_name ;;
        3)  set_android_config ;;
        4)  set_android_signing ;;
        5)  set_ios_display_name ;;
        6)  set_ios_bundle_id ;;
        7)  set_macos_config ;;
        8)  set_windows_config ;;
        9)  set_linux_config ;;
        10) set_web_config ;;
        11) set_backend_version ;;
        12) echo "iOS signing config needs to be done in Xcode."
            read -r -p "Press Enter to return to menu..." ;;
        q|Q) echo "Goodbye!"; exit 0 ;;
        *) echo "Invalid option, please try again" ;;
    esac
    echo ""
    read -r -p "Press Enter to return to menu..."
done
