#!/bin/bash
set -euo pipefail

# ==============================================================================
# Cookie Release & In-App Update Helper Script
# ==============================================================================
# Usage:
#   ./scripts/release_update.sh <version> <build_number> [dmg_path]
#
# Example:
#   ./scripts/release_update.sh 1.0.1 2
# ==============================================================================

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-}"
BUILD="${2:-}"

if [ -z "$VERSION" ] || [ -z "$BUILD" ]; then
    echo "❌ Error: Missing arguments."
    echo "Usage: $0 <version> <build_number> [optional_dmg_path]"
    echo "Example: $0 1.0.1 2"
    exit 1
fi

echo "======================================================"
echo "🍪 Preparing Cookie Release v${VERSION} (Build ${BUILD})"
echo "======================================================"

SPARKLE_BIN="${PROJECT_ROOT}/.build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin"
if [ ! -d "$SPARKLE_BIN" ]; then
    echo "🔍 Locating Sparkle tools..."
    SPARKLE_BIN=$(find "${PROJECT_ROOT}/.build" -name "sign_update" -type f -perm +111 -exec dirname {} \; | head -n 1)
fi

if [ -z "$SPARKLE_BIN" ] || [ ! -x "${SPARKLE_BIN}/sign_update" ]; then
    echo "❌ Error: Sparkle 'sign_update' binary not found. Please resolve SPM packages first."
    exit 1
fi

DMG_PATH="${3:-}"
OUTPUT_DMG="${PROJECT_ROOT}/website/downloads/Cookie-${VERSION}.dmg"

if [ -z "$DMG_PATH" ]; then
    echo "📦 Building Cookie Release via Xcode..."
    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
        -scheme Cookie \
        -configuration Release \
        -derivedDataPath "${PROJECT_ROOT}/.build/DerivedData" \
        MARKETING_VERSION="${VERSION}" \
        CURRENT_PROJECT_VERSION="${BUILD}" \
        build

    BUILT_APP="${PROJECT_ROOT}/.build/DerivedData/Build/Products/Release/Cookie.app"
    if [ ! -d "$BUILT_APP" ]; then
        echo "❌ Error: Build succeeded but Cookie.app was not found at $BUILT_APP"
        exit 1
    fi

    echo "💿 Creating DMG at: $OUTPUT_DMG"
    mkdir -p "${PROJECT_ROOT}/website/downloads"
    hdiutil create -volname "Cookie" -srcfolder "$BUILT_APP" -ov -format UDZO "$OUTPUT_DMG"
    DMG_PATH="$OUTPUT_DMG"
fi

if [ ! -f "$DMG_PATH" ]; then
    echo "❌ Error: DMG not found at $DMG_PATH"
    exit 1
fi

FILE_SIZE=$(stat -f%z "$DMG_PATH")
echo "🔑 Signing update DMG using Sparkle EdDSA key..."
SIGNATURE_OUTPUT=$("${SPARKLE_BIN}/sign_update" "$DMG_PATH")
echo "Result: $SIGNATURE_OUTPUT"

# Extract edSignature
ED_SIGNATURE=$(echo "$SIGNATURE_OUTPUT" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')

if [ -z "$ED_SIGNATURE" ]; then
    echo "❌ Error: Failed to extract edSignature from sign_update output."
    exit 1
fi

PUB_DATE=$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")

echo ""
echo "======================================================"
echo "✅ Update Signed Successfully!"
echo "======================================================"
echo "Version:         ${VERSION}"
echo "Build:           ${BUILD}"
echo "DMG File:        ${DMG_PATH}"
echo "File Size:       ${FILE_SIZE} bytes"
echo "EdDSA Signature: ${ED_SIGNATURE}"
echo ""
echo "📋 Add this <item> block to website/appcast.xml:"
echo "------------------------------------------------------"
cat <<EOF
    <item>
      <title>Cookie ${VERSION}</title>
      <pubDate>${PUB_DATE}</pubDate>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <description><![CDATA[
        <h2>What's New in Cookie ${VERSION}</h2>
        <ul>
          <li>Cozy new improvements and fixes for Cookie.</li>
        </ul>
      ]]></description>
      <enclosure
        url="https://github.com/MdKasif0/Cookie/releases/download/v${VERSION}/Cookie-${VERSION}.dmg"
        sparkle:version="${BUILD}"
        sparkle:shortVersionString="${VERSION}"
        length="${FILE_SIZE}"
        type="application/octet-stream"
        sparkle:edSignature="${ED_SIGNATURE}"/>
    </item>
EOF
echo "------------------------------------------------------"
echo ""
echo "Next steps:"
echo "1. Paste the <item> into website/appcast.xml"
echo "2. Push changes to GitHub (git add, git commit, git push)"
echo "3. Create GitHub Release v${VERSION} and attach Cookie-${VERSION}.dmg"
echo "4. The website and in-app updater will automatically serve the new release!"
