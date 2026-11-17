#!/usr/bin/env bash
# Build, package, sign, and (optionally) publish a Microscope release.
#
# Usage:
#   scripts/release.sh <version-tag>             # build + sign locally
#   scripts/release.sh <version-tag> --upload    # also create/update the GH release
#
# The tag must match CFBundleShortVersionString in Resources/Info.plist
# (tag "v0.1" <-> version "0.1").
#
# Env overrides:
#   RELEASE_SIGNING_KEY  SSH private key used for signing (default ~/.ssh/id_ed25519)
#   RELEASE_PRINCIPAL    Identity in the signature (default release@microscope)
#
# Produces in the repo root:
#   Microscope-<tag>-macos-<arch>.app.zip       (+ .sig SSH signature, + .sha256)
set -euo pipefail

[[ "${OSTYPE:-}" == darwin* ]] || { echo "release.sh: macOS only" >&2; exit 1; }

VERSION="${1:?usage: $0 <version-tag> [--upload]}"
UPLOAD=0
for arg in "${@:2}"; do
    case "$arg" in
        --upload) UPLOAD=1 ;;
        *) echo "release.sh: unknown arg: $arg" >&2; exit 2 ;;
    esac
done

RELEASE_SIGNING_KEY="${RELEASE_SIGNING_KEY:-$HOME/.ssh/id_ed25519}"
RELEASE_PRINCIPAL="${RELEASE_PRINCIPAL:-release@microscope}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
PINNED_PUBKEY="keys/release-signing.pub"

[[ -f "$RELEASE_SIGNING_KEY" ]] || { echo "release.sh: signing key not found at $RELEASE_SIGNING_KEY" >&2; exit 3; }
[[ -f "$PINNED_PUBKEY" ]] || { echo "release.sh: pinned public key missing at $PINNED_PUBKEY" >&2; exit 4; }

PLIST_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
if [[ "v${PLIST_VERSION}" != "$VERSION" ]]; then
    echo "release.sh: tag $VERSION doesn't match Info.plist version $PLIST_VERSION" >&2
    exit 5
fi

step() { printf '\n\033[1;36m▸ %s\033[0m\n' "$*"; }

step "Building Microscope.app"
./build.sh

ARCH=$(uname -m)
ZIP="Microscope-${VERSION}-macos-${ARCH}.app.zip"
SIG="${ZIP}.sig"
SUMS="${ZIP}.sha256"

step "Packaging ${ZIP}"
rm -f "$ZIP" "$SIG" "$SUMS"
# ditto preserves bundle metadata; plain zip mangles symlinks/xattrs in .app bundles.
ditto -c -k --keepParent build/Microscope.app "$ZIP"

step "Checksumming"
shasum -a 256 "$ZIP" > "$SUMS"
cat "$SUMS"

step "Signing with ${RELEASE_SIGNING_KEY} as ${RELEASE_PRINCIPAL}"
ssh-keygen -Y sign -f "$RELEASE_SIGNING_KEY" -n file "$ZIP"

step "Verifying signature against pinned $PINNED_PUBKEY"
ALLOWED_SIGNERS=$(mktemp)
trap 'rm -f "$ALLOWED_SIGNERS"' EXIT
echo "${RELEASE_PRINCIPAL} namespaces=\"file\" $(cat "$PINNED_PUBKEY")" > "$ALLOWED_SIGNERS"
ssh-keygen -Y verify -f "$ALLOWED_SIGNERS" -I "$RELEASE_PRINCIPAL" -n file -s "$SIG" < "$ZIP"

step "Artifacts ready"
ls -la "$ZIP" "$SIG" "$SUMS"

if [[ $UPLOAD -eq 1 ]]; then
    if gh release view "$VERSION" >/dev/null 2>&1; then
        step "Uploading to existing release ${VERSION}"
        gh release upload "$VERSION" "$ZIP" "$SIG" "$SUMS" --clobber
    else
        step "Creating release ${VERSION}"
        gh release create "$VERSION" "$ZIP" "$SIG" "$SUMS" \
            --title "Microscope ${VERSION}" --generate-notes
    fi
else
    echo "  Skipped upload (pass --upload to publish)."
fi
