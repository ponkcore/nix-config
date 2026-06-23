#!/usr/bin/env bash
# Updates oh-my-pi to the latest GitHub release.
# Usage: ./pkgs/oh-my-pi/update.sh [VERSION]
# If VERSION is omitted, fetches `releases/latest` from GitHub API.

set -euo pipefail

REPO="can1357/oh-my-pi"
ASSET="omp-linux-x64"
HERE="$(cd "$(dirname "$0")" && pwd)"
DEFAULT_NIX="$HERE/default.nix"

if [ $# -ge 1 ]; then
  VERSION="${1#v}"
else
  VERSION="$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" | jq -r .tag_name | sed 's/^v//')"
fi

echo "Updating oh-my-pi → v${VERSION}"
URL="https://github.com/${REPO}/releases/download/v${VERSION}/${ASSET}"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
curl -fsSL -o "$TMP/${ASSET}" "$URL"

HASH_SRI="$(nix hash file --type sha256 --sri "$TMP/${ASSET}")"

echo "url:  $URL"
echo "hash: $HASH_SRI"

sed -i -E "s|version = \"[^\"]+\";|version = \"${VERSION}\";|" "$DEFAULT_NIX"
sed -i -E "s|hash = \"sha256-[A-Za-z0-9+/=]+\";|hash = \"${HASH_SRI}\";|" "$DEFAULT_NIX"

echo "Done. Verify with: nix build /etc/nixos#nixosConfigurations.lecoo.config.home-manager.users.oonishi.home.activationPackage"
