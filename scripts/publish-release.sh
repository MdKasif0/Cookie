#!/usr/bin/env bash
# Publishes a Cookie release to GitHub Releases.
#
# Binaries are never committed to the repository. This is the one place they are published.
#
# Usage:
#   scripts/publish-release.sh mac <version> [--dry-run] [--yes]
#   scripts/publish-release.sh windows <version> [--dry-run] [--yes]
#
# The two platforms release independently, so they use different tags:
#   mac      tag v<version>          never marked "latest" (the Sparkle appcast points at it by tag)
#   windows  tag windows-v<version>  marked "latest": the website's Windows download and the update feed
#                                    follow releases/latest
#
# mac needs:      dist/Cookie-<version>.dmg (DMG)            release-notes/<version>.md (NOTES)
# windows needs:  dist/windows/installer/Cookie-Setup.exe (INSTALLER)
#                 release-notes/windows-<version>.md (NOTES)
#                 optional dist/windows/Cookie-Windows-<version>-win-x64-Portable.zip (PORTABLE)
# Override any path with the environment variable shown in brackets.
#
# For Windows, the update manifest is created from the installer and signed with the update signing key:
# COOKIE_UPDATE_SIGNING_KEY (the PEM text) or the file named by COOKIE_UPDATE_SIGNING_KEY_FILE
# (default ~/.cookie-release-keys/windows-update-signing.pem). Tagged CI builds do this automatically.
#
# --dry-run builds and verifies everything in a temporary folder and publishes nothing.
set -euo pipefail

REPO="MdKasif0/Cookie"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

fail() { echo "error: $*" >&2; exit 1; }
usage() { sed -n '2,26p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 2; }

PLATFORM="${1:-}"
VERSION="${2:-}"
[[ "$PLATFORM" == "mac" || "$PLATFORM" == "windows" ]] || usage
[[ -n "$VERSION" && "$VERSION" != --* ]] || usage

DRY_RUN=0
ASSUME_YES=0
for arg in "${@:3}"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        --yes) ASSUME_YES=1 ;;
        *) fail "unknown option: $arg" ;;
    esac
done

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

UPLOADS=()
LATE_UPLOADS=()   # uploaded last, so nothing points at a file that is not there yet

if [[ "$PLATFORM" == "mac" ]]; then
    TAG="v${VERSION}"
    TITLE="Cookie ${VERSION}"
    LATEST_FLAG="--latest=false"
    DMG="${DMG:-dist/Cookie-${VERSION}.dmg}"
    NOTES="${NOTES:-release-notes/${VERSION}.md}"
    [[ -f "$NOTES" ]] || fail "missing $NOTES. Write the release notes first."
    [[ -f "$DMG" ]] || fail "missing $DMG. Build it with Packaging/build_dmg.sh first."
    UPLOADS+=("$DMG")
else
    TAG="windows-v${VERSION}"
    TITLE="Cookie for Windows ${VERSION}"
    LATEST_FLAG="--latest"
    INSTALLER="${INSTALLER:-dist/windows/installer/Cookie-Setup.exe}"
    PORTABLE="${PORTABLE:-dist/windows/Cookie-Windows-${VERSION}-win-x64-Portable.zip}"
    NOTES="${NOTES:-release-notes/windows-${VERSION}.md}"
    KEY_FILE="${COOKIE_UPDATE_SIGNING_KEY_FILE:-$HOME/.cookie-release-keys/windows-update-signing.pem}"
    [[ -f "$NOTES" ]] || fail "missing $NOTES. Write the release notes first."
    [[ -f "$INSTALLER" ]] || fail "missing $INSTALLER. Build it on Windows (GitHub Actions) first."

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

    UPLOADS+=("$INSTALLER")
    [[ -f "$PORTABLE" ]] && UPLOADS+=("$PORTABLE") || echo "    (no portable zip at $PORTABLE; skipping it)"
    LATE_UPLOADS+=("$WORK/windows-update.json" "$WORK/windows-update.json.sig")
fi

echo "==> Checksums"
: > "$WORK/SHA256SUMS.txt"
for file in "${UPLOADS[@]}"; do
    (cd "$(dirname "$file")" && shasum -a 256 "$(basename "$file")") >> "$WORK/SHA256SUMS.txt"
done
cat "$WORK/SHA256SUMS.txt"

if [[ "$DRY_RUN" == 1 ]]; then
    echo "==> Dry run: would publish ${TAG} to ${REPO} (${LATEST_FLAG}) with:"
    printf '    %s\n' "${UPLOADS[@]}" "$WORK/SHA256SUMS.txt" ${LATE_UPLOADS[@]+"${LATE_UPLOADS[@]}"}
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
    gh release create "$TAG" -R "$REPO" --title "$TITLE" --notes-file "$NOTES" "$LATEST_FLAG" --target "$(git rev-parse HEAD)"
fi

echo "==> Uploading the downloads"
gh release upload "$TAG" -R "$REPO" "${UPLOADS[@]}" "$WORK/SHA256SUMS.txt" --clobber

if [[ ${#LATE_UPLOADS[@]} -gt 0 ]]; then
    echo "==> Uploading the signed update feed"
    gh release upload "$TAG" -R "$REPO" "${LATE_UPLOADS[@]}" --clobber
fi

echo
echo "Published: https://github.com/${REPO}/releases/tag/${TAG}"
echo "Next: update the version numbers in website/_redirects and website/releases.js, then commit and push."
