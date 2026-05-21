#!/usr/bin/env bash
# Pulls the latest Devin CLI release manifest and pins it into manifest.json.
# Usage: ./pkgs/devin-cli/update.sh [VERSION]
# If VERSION is omitted, uses static.devin.ai/cli/current/manifest.json.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
MANIFEST="$HERE/manifest.json"

if [ $# -ge 1 ]; then
  VERSION="$1"
  URL="https://static.devin.ai/cli/${VERSION}/manifest.json"
else
  URL="https://static.devin.ai/cli/current/manifest.json"
fi

UP="$(curl -fsSL "$URL")"
VERSION_PIN="$(echo "$UP" | jq -r .version)"
echo "Pinning devin-cli → ${VERSION_PIN}"

# Map upstream platform keys → nixpkgs system identifiers.
echo "$UP" | jq --arg v "$VERSION_PIN" '{
  version: $v,
  platforms: {
    "x86_64-linux":  .platforms["x86_64-unknown-linux"],
    "aarch64-linux": .platforms["aarch64-unknown-linux"]
  }
}' > "$MANIFEST"

echo "Wrote $MANIFEST"
cat "$MANIFEST"
