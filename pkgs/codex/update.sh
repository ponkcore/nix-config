#!/usr/bin/env bash
# Updates the pinned OpenAI Codex CLI release in home/codex.nix.
# Usage: ./pkgs/codex/update.sh [VERSION]
# If VERSION is omitted, fetches the latest rust-v* release from GitHub API.

set -euo pipefail

REPO="openai/codex"
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
CODEX_NIX="$ROOT/home/codex.nix"

if [ $# -ge 1 ]; then
  VERSION="${1#v}"
  VERSION="${VERSION#rust-v}"
else
  VERSION="$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
    | jq -r .tag_name | sed 's/^rust-v//')"
fi

if [ -z "$VERSION" ] || [ "$VERSION" = "null" ]; then
  echo "ERROR: could not resolve codex version" >&2
  exit 1
fi

echo "Updating codex → v${VERSION}"
URL="https://github.com/${REPO}/releases/download/rust-v${VERSION}/codex-package-x86_64-unknown-linux-musl.tar.gz"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
curl -fsSL -o "$TMP/codex.tar.gz" "$URL"

HASH_SRI="$(nix hash file --type sha256 --sri "$TMP/codex.tar.gz")"

echo "url:  $URL"
echo "hash: $HASH_SRI"

sed -i -E "s|version = \"[^\"]+\";|version = \"${VERSION}\";|" "$CODEX_NIX"
sed -i -E "s|hash = \"sha256-[A-Za-z0-9+/=]+\";|hash = \"${HASH_SRI}\";|" "$CODEX_NIX"

echo "Building and switching to codex v${VERSION}..."
cd "$ROOT"
sudo nixos-rebuild switch

echo "Done. codex is now at $(codex --version 2>&1 | head -1)"
