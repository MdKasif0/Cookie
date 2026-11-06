#!/bin/bash
set -euo pipefail

# ==============================================================================
# Cookie for Windows - Repeatable Release & Distribution Automation Script
# Phase 5: Premium Polish, Distribution, Updates, and Release
# ==============================================================================

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

VERSION="1.1.0"
DIST_DIR="${PROJECT_ROOT}/dist/windows"
WIN_X64_DIR="${DIST_DIR}/win-x64"
FRAMEWORK_DIR="${DIST_DIR}/framework-dependent"

echo "======================================================================"
echo "🍪 Building Cookie for Windows Release v${VERSION}"
echo "======================================================================"

# 1. Locate dotnet CLI
if command -v dotnet >/dev/null 2>&1; then
    DOTNET_CMD="dotnet"
elif [ -f "$HOME/.dotnet/dotnet" ]; then
    DOTNET_CMD="$HOME/.dotnet/dotnet"
else
    echo "❌ Error: .NET SDK (dotnet) not found in PATH or $HOME/.dotnet/dotnet."
    exit 1
fi

echo "Using .NET SDK: $($DOTNET_CMD --version)"

# 2. Restore Dependencies
echo ""
echo "📦 Step 1: Restoring solution dependencies..."
$DOTNET_CMD restore Cookie.Windows.sln

# 3. Execute Unit Tests
echo ""
echo "🧪 Step 2: Executing full test suite in Release configuration..."
$DOTNET_CMD test Cookie.Windows.Tests/Cookie.Windows.Tests.csproj -c Release --no-restore

# 4. Clean and Prepare Output Directory
echo ""
echo "📁 Step 3: Preparing distribution directories..."
rm -rf "$DIST_DIR"
mkdir -p "$WIN_X64_DIR"
mkdir -p "$FRAMEWORK_DIR"
mkdir -p "${DIST_DIR}/installer"

# 5. Publish Self-Contained win-x64 Application
echo ""
echo "🚀 Step 4: Publishing self-contained win-x64 binaries..."
$DOTNET_CMD publish Cookie.Windows/Cookie.Windows.csproj \
    -c Release \
    -r win-x64 \
    --self-contained true \
    -o "$WIN_X64_DIR"

# 6. Publish Framework-Dependent Application
echo ""
echo "🚀 Step 5: Publishing framework-dependent binaries..."
$DOTNET_CMD publish Cookie.Windows/Cookie.Windows.csproj \
    -c Release \
    -o "$FRAMEWORK_DIR"

# 7. Asset Verification
echo ""
echo "🔍 Step 6: Verifying required application assets..."
REQUIRED_ASSETS=(
    "$WIN_X64_DIR/Cookie.exe"
    "$WIN_X64_DIR/Resources/Cookie.ico"
    "$WIN_X64_DIR/Resources/AssetManifest.json"
    "$WIN_X64_DIR/Resources/Sounds/cookie-meow.wav"
    "$WIN_X64_DIR/Resources/Sounds/cookie-purr.wav"
    "$WIN_X64_DIR/Resources/Sounds/cookie-welcome.wav"
    "$WIN_X64_DIR/Resources/Sprites/Cookie/Emotes/Happy/happy.png"
    "$WIN_X64_DIR/Resources/Sprites/Cookie/Emotes/Love/love.png"
    "$WIN_X64_DIR/Resources/Sprites/Cookie/Emotes/Wave/wave.png"
    "$WIN_X64_DIR/Resources/Sprites/Cookie/Walk/walk.png"
    "$WIN_X64_DIR/Resources/Sprites/Cookie/Items/yarnBall.png"
    "$WIN_X64_DIR/Resources/Sprites/Cookie/Items/cozy-bed.png"
    "$WIN_X64_DIR/Resources/Sprites/Cookie/Emotes/wave.png"
    "$WIN_X64_DIR/Resources/Sprites/Cookie/Emotes/Sleepy/sleepy.png"
    "$WIN_X64_DIR/Resources/Sprites/Cookie/Emotes/Playful/playful.png"
)

for asset in "${REQUIRED_ASSETS[@]}"; do
    if [ ! -f "$asset" ]; then
        echo "❌ Missing required release asset: $asset"
        exit 1
    fi
done
echo "✅ All required assets present and verified."

# 8. Package Portable Archive
echo ""
echo "📦 Step 7: Packaging portable zip distribution..."
PORTABLE_ZIP="${DIST_DIR}/Cookie-Windows-${VERSION}-win-x64-Portable.zip"
(
    cd "$WIN_X64_DIR"
    zip -r -q "$PORTABLE_ZIP" .
)
echo "✅ Created portable archive: $(basename "$PORTABLE_ZIP")"

# 9. Compute Checksums
echo ""
echo "🔐 Step 8: Computing SHA-256 integrity checksums..."
EXE_HASH=$(shasum -a 256 "$WIN_X64_DIR/Cookie.exe" | cut -d ' ' -f 1)
ZIP_HASH=$(shasum -a 256 "$PORTABLE_ZIP" | cut -d ' ' -f 1)
ZIP_SIZE=$(stat -f%z "$PORTABLE_ZIP")

CHECKSUM_FILE="${DIST_DIR}/SHA256SUMS.txt"
cat <<EOF > "$CHECKSUM_FILE"
$EXE_HASH  win-x64/Cookie.exe
$ZIP_HASH  $(basename "$PORTABLE_ZIP")
EOF
echo "✅ Checksums written to SHA256SUMS.txt"

# 10. The update manifest is made at publish time, not here.
# It must describe the installer (Cookie-Setup.exe), which only exists after Inno Setup runs on
# Windows, and it must be signed. An earlier version of this script wrote a manifest here that
# paired the installer's address with the portable zip's checksum, which would fail every update.
# See scripts/publish-release.sh and the "Publishing a release" section of DISTRIBUTION.md.
MANIFEST_FILE="(made by scripts/publish-release.sh)"

# 11. Compile Inno Setup Installer if Inno Setup is available
echo ""
echo "💿 Step 10: Checking for Inno Setup compiler (iscc)..."
if command -v iscc >/dev/null 2>&1; then
    echo "Running Inno Setup compiler..."
    iscc "${PROJECT_ROOT}/Packaging/windows/CookieSetup.iss"
    echo "✅ Installer compiled successfully!"
else
    echo "ℹ️  Inno Setup compiler (iscc) not installed on this host (macOS build environment)."
    echo "   The Inno Setup script is prepared and verified at Packaging/windows/CookieSetup.iss."
    echo "   On Windows build agents or GitHub Actions, run: iscc Packaging/windows/CookieSetup.iss"
fi

echo ""
echo "======================================================================"
echo "🎉 Cookie for Windows Release Build Complete!"
echo "======================================================================"
echo "Version:         ${VERSION}"
echo "Portable Zip:    ${PORTABLE_ZIP} (${ZIP_SIZE} bytes)"
echo "Portable SHA256: ${ZIP_HASH}"
echo "Executable SHA:  ${EXE_HASH}"
echo "Manifest:        ${MANIFEST_FILE}"
echo "Installer Spec:  Packaging/windows/CookieSetup.iss"
echo "======================================================================"
