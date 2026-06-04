#!/usr/bin/env bash
# build_package.sh - Build AI Agent Flutter app with backend Fat JAR
# Usage:
#   ./build_package.sh -t windows    # Build Windows
#   ./build_package.sh -t android    # Build Android
#   ./build_package.sh -t linux      # Build Linux
#   ./build_package.sh -t macos      # Build macOS
#   ./build_package.sh -t ios        # Build iOS (macOS host only)
#   ./build_package.sh -t all        # Build all platforms
#   ./build_package.sh -t desktop    # Build all desktop platforms (windows+linux+macos)

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
JAR_DIR="$ROOT_DIR/backend_kotlin/build/libs"
JAR_FILE="$JAR_DIR/ai_agent_backend.jar"

# Platforms that need the backend JAR
NEEDS_JAR="windows linux macos"

print_banner() {
    echo "========================================"
    echo "  AI Agent Build Script"
    echo "========================================"
    echo ""
}

usage() {
    echo "Usage: $0 -t <target>"
    echo "  Targets: windows, android, linux, macos, ios, all, desktop"
    exit 1
}

# Parse arguments
TARGET=""
while getopts "t:" opt; do
    case $opt in
        t) TARGET="$OPTARG" ;;
        *) usage ;;
    esac
done

if [ -z "$TARGET" ]; then
    usage
fi

# Validate target
case "$TARGET" in
    windows|android|linux|macos|ios|all|desktop) ;;
    *) echo "Error: Unknown target '$TARGET'"; usage ;;
esac

print_banner

# ============================================
# Step 1: Build backend Fat JAR (desktop only)
# ============================================
needs_jar() {
    case "$TARGET" in
        windows|linux|macos|all|desktop) return 0 ;;
        *) return 1 ;;
    esac
}

if needs_jar; then
    echo "[1/3] Building backend Fat JAR..."
    pushd "$ROOT_DIR/backend_kotlin" > /dev/null
    ./gradlew buildFatJar
    if [ $? -ne 0 ]; then
        echo "  [FAIL] Gradle build failed"
        exit 1
    fi
    popd > /dev/null
    echo "  [OK] Backend Fat JAR: $JAR_FILE"
else
    echo "[1/3] Skipping backend JAR (not needed for $TARGET)"
fi

# ============================================
# Step 2: Get Flutter version
# ============================================
echo "[2/3] Getting Flutter version..."
VERSION=$(grep -E '^version:' "$ROOT_DIR/pubspec.yaml" | sed 's/version:[[:space:]]*//')
VERSION="${VERSION:-1.0.0}"
echo "  Version: $VERSION"

# ============================================
# Step 3: Build Flutter by target
# ============================================

build_windows() {
    echo "[3/3] Building Flutter Windows..."

    pushd "$ROOT_DIR" > /dev/null
    flutter build windows --release
    popd > /dev/null

    # Copy JAR to output
    OUTPUT_DIR="$ROOT_DIR/build/windows/x64/runner/Release/backend"
    mkdir -p "$OUTPUT_DIR"
    cp "$JAR_FILE" "$OUTPUT_DIR/ai_agent_backend.jar"

    echo "  [OK] JAR copied to: $OUTPUT_DIR/ai_agent_backend.jar"
    echo ""
    echo "Output: $ROOT_DIR/build/windows/x64/runner/Release/"
    echo "  Exe: 星火学伴.exe"
    echo "  JAR: backend/ai_agent_backend.jar"
}

build_android() {
    echo "[3/3] Building Flutter Android..."

    pushd "$ROOT_DIR" > /dev/null
    flutter build apk --release
    popd > /dev/null

    echo ""
    echo "Output: $ROOT_DIR/build/app/outputs/flutter-apk/"
    echo "  APK: app-release.apk"
}

build_linux() {
    echo "[3/3] Building Flutter Linux..."

    pushd "$ROOT_DIR" > /dev/null
    flutter build linux --release
    popd > /dev/null

    # Copy JAR to output
    OUTPUT_DIR="$ROOT_DIR/build/linux/x64/release/bundle/backend"
    mkdir -p "$OUTPUT_DIR"
    cp "$JAR_FILE" "$OUTPUT_DIR/ai_agent_backend.jar"

    echo "  [OK] JAR copied to: $OUTPUT_DIR/ai_agent_backend.jar"
    echo ""
    echo "Output: $ROOT_DIR/build/linux/x64/release/bundle/"
    echo "  Binary: 星火学伴 (ELF)"
    echo "  JAR:    backend/ai_agent_backend.jar"
}

build_macos() {
    echo "[3/3] Building Flutter macOS..."

    pushd "$ROOT_DIR" > /dev/null
    flutter build macos --release
    popd > /dev/null

    # Copy JAR into the .app bundle's Resources folder
    APP_BUNDLE=$(find "$ROOT_DIR/build/macos/Build/Products/Release" -maxdepth 1 -name '*.app' -type d | head -1)
    if [ -n "$APP_BUNDLE" ]; then
        RESOURCES_DIR="$APP_BUNDLE/Contents/Resources/backend"
        mkdir -p "$RESOURCES_DIR"
        cp "$JAR_FILE" "$RESOURCES_DIR/ai_agent_backend.jar"
        echo "  [OK] JAR copied to: $RESOURCES_DIR/ai_agent_backend.jar"
    else
        echo "  [WARN] Could not find .app bundle, JAR not copied"
    fi

    echo ""
    echo "Output: $ROOT_DIR/build/macos/Build/Products/Release/"
    echo "  App:  星火学伴.app"
    echo "  JAR:  backend/ai_agent_backend.jar (inside .app bundle)"
}

build_ios() {
    echo "[3/3] Building Flutter iOS..."

    if [ "$(uname)" != "Darwin" ]; then
        echo "  [ERROR] iOS builds are only supported on macOS."
        exit 1
    fi

    pushd "$ROOT_DIR" > /dev/null
    flutter precache --ios
    echo "  Building iOS release (this may take a while)..."
    flutter build ios --release --no-codesign
    popd > /dev/null

    echo ""
    echo "Output: $ROOT_DIR/build/ios/iphoneos/Runner.app/"
    echo "  App: Runner.app"
    echo ""
    echo "  [TIP] To produce an IPA for distribution, run:"
    echo "    flutter build ipa --release"
    echo "  (requires valid Apple Developer certificate & provisioning profile)"
}

build_desktop() {
    echo "--- Building Desktop Platforms ---"
    build_windows
    echo ""
    build_linux
    echo ""
    build_macos
}

# Run target
case "$TARGET" in
    windows) build_windows ;;
    android) build_android ;;
    linux)   build_linux ;;
    macos)   build_macos ;;
    ios)     build_ios ;;
    desktop) build_desktop ;;
    all)
        echo "--- Building ALL Platforms ---"
        build_windows
        echo ""
        build_linux
        echo ""
        build_macos
        echo ""
        build_android
        echo ""
        build_ios
        ;;
esac

echo ""
echo "========================================"
echo "  [Done] Build complete!"
echo "========================================"
