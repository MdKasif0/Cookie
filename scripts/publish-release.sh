#!/usr/bin/env bash
# Publishes a Cookie release to GitHub Releases and builds the signed Windows update feed.
#
# Binaries are never committed to the repository. This is the one place they are published.
#
# Usage:
#   scripts/publish-release.sh <version> [--dry-run] [--yes]
#
# It looks for these files (override a path with the environment variable shown):
#   dist/Cookie-<version>.dmg                          the Mac disk image        (DMG)
#   dist/windows/installer/Cookie-Setup.exe            the Windows installer     (INSTALLER)
#   dist/windows/Cookie-Windows-<version>-win-x64-Portable.zip                   (PORTABLE)
#   release-notes/<version>.md                         the release notes         (NOTES)
#
# The Windows update manifest is created from the installer and signed with the update
# signing key: COOKIE_UPDATE_SIGNING_KEY (the PEM text) or the file named by
# COOKIE_UPDATE_SIGNING_KEY_FILE (default ~/.cookie-release-keys/windows-update-signing.pem).
#
# --dry-run builds and verifies everything in a temporary folder and publishes nothing.
set -euo pipefail

REPO="MdKasif0/Cookie"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

VERSION="${1:-}"
DRY_RUN=0
ASSUME_YES=0
for arg in "${@:2}"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        --yes) ASSUME_YES=1 ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done
if [[ -z "$VERSION" || "$VERSION" == --* ]]; then
    sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 2
fi

TAG="v${VERSION}"
DMG="${DMG:-dist/Cookie-${VERSION}.dmg}"
INSTALLER="${INSTALLER:-dist/windows/installer/Cookie-Setup.exe}"
PORTABLE="${PORTABLE:-dist/windows/Cookie-Windows-${VERSION}-win-x64-Portable.zip}"
NOTES="${NOTES:-release-notes/${VERSION}.md}"
KEY_FILE="${COOKIE_UPDATE_SIGNING_KEY_FILE:-$HOME/.cookie-release-keys/windows-update-signing.pem}"

fail() { echo "error: $*" >&2; exit 1; }

[[ -f "$NOTES" ]] || fail "missing $NOTES. Write the release notes first."
[[ -f "$INSTALLER" ]] || fail "missing $INSTALLER. Build it on Windows (GitHub Actions) first."

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if [[ -z "${COOKIE_UPDATE_SIGNING_KEY:-}" ]]; then
    [[ -f "$KEY_FILE" ]] || fail "no signing key. Set COOKIE_UPDATE_SIGNING_KEY or create $KEY_FILE (see DISTRIBUTION.md)."
    KEY_ARGS=(--key-file "$KEY_FILE")
else
    KEY_ARGS=()
fi

TOOL=(dotnet run --project Tools/CookieUpdateTool -c Release --)

echo "==> Building the signed Windows update manifest"
"${TOOL[@]}" manifest \
    --version "$VERSION" \
    --installer "$INSTALLER" \
    --url "https://github.com/${REPO}/releases/download/${TAG}/Cookie-Setup.exe" \
    --notes-file "$NOTES" \
    --out "$WORK/windows-update.json"
# A non-zero exit here includes "this key is not trusted by the app".
"${TOOL[@]}" sign "$WORK/windows-update.json" ${KEY_ARGS[@]+"${KEY_ARGS[@]}"}
"${TOOL[@]}" verify "$WORK/windows-update.json"

echo "==> Checksums"
UPLOADS=("$INSTALLER")
[[ -f "$DMG" ]] && UPLOADS+=("$DMG") || echo "    (no Mac DMG at $DMG; skipping it)"
[[ -f "$PORTABLE" ]] && UPLOADS+=("$PORTABLE") || echo "    (no portable zip at $PORTABLE; skipping it)"
: > "$WORK/SHA256SUMS.txt"
for file in "${UPLOADS[@]}"; do
    (cd "$(dirname "$file")" && shasum -a 256 "$(basename "$file")") >> "$WORK/SHA256SUMS.txt"
done
cat "$WORK/SHA256SUMS.txt"

if [[ "$DRY_RUN" == 1 ]]; then
    echo "==> Dry run: would publish ${TAG} to ${REPO} with:"
    printf '    %s\n' "${UPLOADS[@]}" "$WORK/SHA256SUMS.txt" windows-update.json windows-update.json.sig
    exit 0
fi

command -v gh >/dev/null || fail "the GitHub CLI (gh) is required."
gh auth status >/dev/null 2>&1 || fail "run 'gh auth login' first."

echo
echo "About to publish ${TAG} to https://github.com/${REPO}/releases (public)."
if [[ "$ASSUME_YES" != 1 ]]; then
    read -r -p "Continue? [y/N] " answer
    [[ "$answer" == "y" || "$answer" == "Y" ]] || fail "cancelled."
fi

if gh release view "$TAG" -R "$REPO" >/dev/null 2>&1; then
    echo "==> Release ${TAG} exists; adding files to it"
else
    echo "==> Creating release ${TAG}"
    gh release create "$TAG" -R "$REPO" --title "Cookie ${VERSION}" --notes-file "$NOTES" --target "$(git rev-parse HEAD)"
fi

echo "==> Uploading the downloads"
gh release upload "$TAG" -R "$REPO" "${UPLOADS[@]}" "$WORK/SHA256SUMS.txt" --clobber

# The update feed goes last, so installed apps never see a manifest whose installer is missing.
echo "==> Uploading the signed update feed"
gh release upload "$TAG" -R "$REPO" "$WORK/windows-update.json" "$WORK/windows-update.json.sig" --clobber

echo
echo "Published: https://github.com/${REPO}/releases/tag/${TAG}"
echo "Next: update the version numbers in website/_redirects and website/releases.js, then commit and push."
