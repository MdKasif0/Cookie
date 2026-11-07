#!/usr/bin/env bash
set -euo pipefail

# Cookie macOS Production DMG Packaging Script
#
# With no environment set, this produces an ad-hoc signed development DMG that
# Gatekeeper blocks on other Macs. For a release that opens without warnings:
#
#   COOKIE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
#   COOKIE_TEAM_ID="TEAMID"
#   COOKIE_NOTARY_PROFILE="CookieNotary"    # from: xcrun notarytool store-credentials
#
# See DISTRIBUTION.md for how to obtain these.
SIGN_IDENTITY="${COOKIE_SIGN_IDENTITY:-}"
TEAM_ID="${COOKIE_TEAM_ID:-}"
NOTARY_PROFILE="${COOKIE_NOTARY_PROFILE:-}"

if [[ -n "${SIGN_IDENTITY}" && -z "${TEAM_ID}" ]]; then
    echo "error: COOKIE_TEAM_ID is required when COOKIE_SIGN_IDENTITY is set." >&2
    exit 1
fi
if [[ -n "${NOTARY_PROFILE}" && -z "${SIGN_IDENTITY}" ]]; then
    echo "error: notarization requires COOKIE_SIGN_IDENTITY." >&2
    exit 1
fi

# Signs one path with Hardened Runtime and a secure timestamp.
sign_path() {
    codesign --force --options runtime --timestamp --sign "${SIGN_IDENTITY}" "$@"
}

# Signs inside-out, as Sparkle documents for Developer ID distribution.
# `codesign --deep` is deliberately avoided: it can drop nested entitlements.
sign_app_bundle() {
    local app="$1"
    local sparkle="${app}/Contents/Frameworks/Sparkle.framework"
    sign_path "${sparkle}/Versions/B/XPCServices/Installer.xpc"
    sign_path --preserve-metadata=entitlements "${sparkle}/Versions/B/XPCServices/Downloader.xpc"
    sign_path "${sparkle}/Versions/B/Autoupdate"
    sign_path "${sparkle}/Versions/B/Updater.app"
    sign_path "${sparkle}"
    sign_path "${app}"
    codesign --verify --deep --strict --verbose=2 "${app}"
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DIST_DIR="${PROJECT_ROOT}/dist"
APP_NAME="Cookie"
VERSION="1.3.0"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
VOL_NAME="${APP_NAME}"
RELEASE_APP="${PROJECT_ROOT}/.build/DerivedData/Build/Products/Release/${APP_NAME}.app"
STAGING_DIR="${DIST_DIR}/staging"
TEMP_DMG="${DIST_DIR}/temp.dmg"
FINAL_DMG="${DIST_DIR}/${DMG_NAME}"

echo "==> 1. Ensuring clean distribution directories..."
# Only this script's own outputs: dist/windows belongs to the Windows build.
rm -rf "${STAGING_DIR}" "${TEMP_DMG}" "${FINAL_DMG}"
mkdir -p "${DIST_DIR}" "${STAGING_DIR}"

echo "==> 2. Building fresh Release application bundle..."
BUILD_SETTINGS=()
if [[ -n "${SIGN_IDENTITY}" ]]; then
    BUILD_SETTINGS+=(
        "CODE_SIGN_IDENTITY=${SIGN_IDENTITY}"
        "DEVELOPMENT_TEAM=${TEAM_ID}"
        "ENABLE_HARDENED_RUNTIME=YES"
        "CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO"
        "OTHER_CODE_SIGN_FLAGS=--timestamp"
    )
fi
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme Cookie -configuration Release -derivedDataPath "${PROJECT_ROOT}/.build/DerivedData" build ${BUILD_SETTINGS[@]+"${BUILD_SETTINGS[@]}"}

echo "==> 3. Populating staging directory..."
cp -R "${RELEASE_APP}" "${STAGING_DIR}/${APP_NAME}.app"
if [[ -n "${SIGN_IDENTITY}" ]]; then
    echo "    Signing with: ${SIGN_IDENTITY}"
    sign_app_bundle "${STAGING_DIR}/${APP_NAME}.app"
fi
ln -s /Applications "${STAGING_DIR}/Applications"

# Custom DMG Volume Icon
cp "${PROJECT_ROOT}/Cookie/Resources/AppIcon.icns" "${STAGING_DIR}/.VolumeIcon.icns"

# Background artwork
mkdir -p "${STAGING_DIR}/.background"
cp "${SCRIPT_DIR}/dmg_background.png" "${STAGING_DIR}/.background/dmg_background.png"
if [[ -f "${SCRIPT_DIR}/dmg_background@2x.png" ]]; then
    cp "${SCRIPT_DIR}/dmg_background@2x.png" "${STAGING_DIR}/.background/dmg_background@2x.png"
fi
if [[ -f "${SCRIPT_DIR}/dmg_background.tiff" ]]; then
    cp "${SCRIPT_DIR}/dmg_background.tiff" "${STAGING_DIR}/.background/dmg_background.tiff"
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

# Set custom volume icon attribute
if [[ -f "/Volumes/${VOL_NAME}/.VolumeIcon.icns" ]]; then
    /usr/bin/SetFile -a C "/Volumes/${VOL_NAME}" || true
    /usr/bin/SetFile -a V "/Volumes/${VOL_NAME}/.VolumeIcon.icns" || true
fi

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
            set background picture of theViewOptions to file ".background:dmg_background.tiff"
        on error
            try
                set background picture of theViewOptions to file ".background:dmg_background.png"
            end try
        end try
        
        set position of item "${APP_NAME}.app" of container window to {180, 210}
        set position of item "Applications" of container window to {475, 210}
        
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

if [[ -n "${SIGN_IDENTITY}" ]]; then
    echo "==> 10. Signing disk image..."
    codesign --force --timestamp --sign "${SIGN_IDENTITY}" "${FINAL_DMG}"
    RELEASE_STATUS="Developer ID signed, NOT notarized (set COOKIE_NOTARY_PROFILE)"
else
    RELEASE_STATUS="Ad-hoc development build: Gatekeeper will block this on other Macs"
fi

if [[ -n "${NOTARY_PROFILE}" ]]; then
    echo "==> 11. Notarizing (this usually takes a few minutes)..."
    xcrun notarytool submit "${FINAL_DMG}" --keychain-profile "${NOTARY_PROFILE}" --wait
    # stapler fails unless Apple accepted the submission, so a rejected build
    # stops here. Inspect it with: xcrun notarytool log <submission-id>
    xcrun stapler staple "${FINAL_DMG}"
    xcrun stapler validate "${FINAL_DMG}"
    spctl --assess --type open --context context:primary-signature --verbose=2 "${FINAL_DMG}"
    RELEASE_STATUS="Developer ID signed, notarized and stapled"
fi

echo "========================================================"
echo " Cookie distribution DMG generated successfully!"
echo " Path: ${FINAL_DMG}"
echo " Trust: ${RELEASE_STATUS}"
echo " Size: $(ls -lh "${FINAL_DMG}" | awk '{print $5}')"
echo "========================================================"
