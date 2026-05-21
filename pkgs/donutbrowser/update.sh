#!/usr/bin/env bash
# Updates donutbrowser to the latest GitHub release.
# Usage: ./pkgs/donutbrowser/update.sh [VERSION]
# If VERSION is omitted, fetches `releases/latest` from GitHub API.

set -euo pipefail

REPO="zhom/donutbrowser"
HERE="$(cd "$(dirname "$0")" && pwd)"
DEFAULT_NIX="$HERE/default.nix"

if [ $# -ge 1 ]; then
  VERSION="$1"
else
  VERSION="$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" | jq -r .tag_name | sed 's/^v//')"
fi
echo "Updating donutbrowser → v${VERSION}"

URL="https://github.com/${REPO}/releases/download/v${VERSION}/Donut_${VERSION}_amd64.AppImage"

# Download (cache in /tmp) and compute SRI hash via nix-hash.
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
curl -fsSL -o "$TMP/img" "$URL"

HASH_HEX="$(sha256sum "$TMP/img" | awk '{print $1}')"
HASH_SRI="sha256-$(echo -n "$HASH_HEX" | xxd -r -p | base64)"
echo "url:  $URL"
echo "hash: $HASH_SRI"

# Patch version + hash in default.nix
sed -i -E "s|version = \"[^\"]+\";|version = \"${VERSION}\";|" "$DEFAULT_NIX"
sed -i -E "s|hash = \"sha256-[A-Za-z0-9+/=]+\";|hash = \"${HASH_SRI}\";|" "$DEFAULT_NIX"

echo "Done. Verify with: nix flake check"
