#!/usr/bin/env bash
set -euo pipefail

# Cookie macOS Production DMG Packaging Script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DIST_DIR="${PROJECT_ROOT}/dist"
APP_NAME="Cookie"
VERSION="1.0.0"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
VOL_NAME="${APP_NAME}"
RELEASE_APP="${PROJECT_ROOT}/.build/DerivedData/Build/Products/Release/${APP_NAME}.app"
STAGING_DIR="${DIST_DIR}/staging"
TEMP_DMG="${DIST_DIR}/temp.dmg"
FINAL_DMG="${DIST_DIR}/${DMG_NAME}"

echo "==> 1. Ensuring clean distribution directories..."
rm -rf "${DIST_DIR}"
mkdir -p "${DIST_DIR}" "${STAGING_DIR}"

echo "==> 2. Verifying Release application bundle..."
if [[ ! -d "${RELEASE_APP}" ]]; then
    echo "Release app bundle not found at ${RELEASE_APP}. Building now..."
    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme Cookie -configuration Release -derivedDataPath "${PROJECT_ROOT}/.build/DerivedData" build
fi

echo "==> 3. Populating staging directory..."
cp -R "${RELEASE_APP}" "${STAGING_DIR}/${APP_NAME}.app"
ln -s /Applications "${STAGING_DIR}/Applications"

# Background artwork
mkdir -p "${STAGING_DIR}/.background"
cp "${SCRIPT_DIR}/dmg_background.png" "${STAGING_DIR}/.background/dmg_background.png"
if [[ -f "${SCRIPT_DIR}/dmg_background@2x.png" ]]; then
    cp "${SCRIPT_DIR}/dmg_background@2x.png" "${STAGING_DIR}/.background/dmg_background@2x.png"
fi

echo "==> 4. Creating temporary read-write disk image..."
hdiutil create -srcfolder "${STAGING_DIR}" \
               -volname "${VOL_NAME}" \
               -fs HFS+ \
               -fsargs "-c c=64,a=16,e=16" \
               -format UDRW \
               -size 250m \
               "${TEMP_DMG}"

echo "==> 5. Mounting disk image for Finder styling..."
DEVICE=$(hdiutil attach -readwrite -noverify -noautoopen "${TEMP_DMG}" | awk 'NR==1{print $1}')
sleep 2

echo "==> 6. Applying minimal premium Finder presentation..."
osascript <<APPLESCRIPT || true
tell application "Finder"
    tell disk "${VOL_NAME}"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {120, 120, 760, 560}
        
        set theViewOptions to the icon view options of container window
        set icon size of theViewOptions to 104
        set text size of theViewOptions to 12
        set arrangement of theViewOptions to not arranged
        
        try
            set background picture of theViewOptions to file ".background:dmg_background.png"
        end try
        
        set position of item "${APP_NAME}.app" of container window to {160, 230}
        set position of item "Applications" of container window to {480, 230}
        
        close
        open
        update without registering applications
        delay 1
    end tell
end tell
APPLESCRIPT

sync
sleep 2

echo "==> 7. Unmounting disk image..."
hdiutil detach "${DEVICE}" || hdiutil detach -force "${DEVICE}"

echo "==> 8. Compressing final DMG with UDZO..."
hdiutil convert "${TEMP_DMG}" -format UDZO -imagekey zlib-level=9 -o "${FINAL_DMG}"

echo "==> 9. Cleaning up temporary artifacts..."
rm -f "${TEMP_DMG}"
rm -rf "${STAGING_DIR}"

echo "========================================================"
echo " Cookie distribution DMG generated successfully!"
echo " Path: ${FINAL_DMG}"
echo " Size: $(ls -lh "${FINAL_DMG}" | awk '{print $5}')"
echo "========================================================"
