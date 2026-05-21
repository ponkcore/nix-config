#!/usr/bin/env bash
# Bumps the gptme derivation to a specific upstream tag.
# Usage: pkgs/gptme/update.sh vX.Y.Z
# Rewrites manifest.json with the new revision and prefetched sha256.

set -euo pipefail

if [ $# -lt 1 ]; then
  echo "usage: $0 vX.Y.Z" >&2
  echo "  example: $0 v0.31.0" >&2
  exit 2
fi

VERSION_TAG="$1"
VERSION_PIN="${VERSION_TAG#v}"

HERE="$(cd "$(dirname "$0")" && pwd)"
MANIFEST="$HERE/manifest.json"

echo "Pinning gptme → ${VERSION_TAG}"
PREFETCH="$(nix run nixpkgs#nix-prefetch-github -- gptme gptme --rev "$VERSION_TAG")"

HASH="$(echo "$PREFETCH" | jq -r .hash)"

jq -n \
  --arg version "$VERSION_PIN" \
  --arg rev "$VERSION_TAG" \
  --arg hash "$HASH" \
  '{
     version: $version,
     src: {
       owner: "gptme",
       repo: "gptme",
       rev: $rev,
       hash: $hash,
     },
   }' > "$MANIFEST"

echo "Wrote $MANIFEST"
cat "$MANIFEST"
