#!/usr/bin/env bash
# Updates the Nix-store packaged oh-my-openagent OpenCode plugin.
# Usage: ./pkgs/oh-my-openagent/update.sh [VERSION]
# If VERSION is omitted, fetches the npm `latest` dist-tag.

set -euo pipefail

PACKAGE="oh-my-openagent"
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
DEFAULT_NIX="$HERE/default.nix"

if [ $# -ge 1 ]; then
  VERSION="${1#v}"
else
  VERSION="$(curl -fsSL "https://registry.npmjs.org/${PACKAGE}/latest" | jq -r .version)"
fi

if [ -z "$VERSION" ] || [ "$VERSION" = null ]; then
  echo "ERROR: could not resolve ${PACKAGE} version" >&2
  exit 1
fi

echo "Updating ${PACKAGE} → v${VERSION}"
URL="https://registry.npmjs.org/${PACKAGE}/-/${PACKAGE}-${VERSION}.tgz"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
curl -fsSL -o "$TMP/${PACKAGE}.tgz" "$URL"
SRC_HASH="$(nix hash file --type sha256 --sri "$TMP/${PACKAGE}.tgz")"

tar -xzf "$TMP/${PACKAGE}.tgz" -C "$TMP"
(
  cd "$TMP/package"
  jq '
    del(.devDependencies)
    | del(.workspaces)
    | del(.scripts.prepare)
    | del(.scripts.postinstall)
    | del(.scripts.prepack)
    | del(.scripts.prepublishOnly)
  ' package.json > "$HERE/package.json"
  cp "$HERE/package.json" package.json
  nix shell "$ROOT#nixosConfigurations.lecoo.pkgs.nodejs_22" -c npm install --package-lock-only --ignore-scripts >/dev/null
  cp package-lock.json "$HERE/package-lock.json"
)

sed -i -E "s|version = \"[^\"]+\";|version = \"${VERSION}\";|" "$DEFAULT_NIX"
sed -i -E "s|hash = \"sha256-[^\"]+\";|hash = \"${SRC_HASH}\";|" "$DEFAULT_NIX"
sed -i -E "s|npmDepsHash = \"sha256-[^\"]+\";|npmDepsHash = lib.fakeHash;|" "$DEFAULT_NIX"

set +e
BUILD_LOG="$(nix build "$ROOT#nixosConfigurations.lecoo.pkgs.oh-my-openagent" --show-trace 2>&1)"
BUILD_STATUS=$?
set -e

if [ "$BUILD_STATUS" -eq 0 ]; then
  echo "ERROR: expected fake npmDepsHash build to fail, but it succeeded" >&2
  exit 1
fi

DEPS_HASH="$(printf '%s\n' "$BUILD_LOG" | sed -n 's/.*got:[[:space:]]*\(sha256-[A-Za-z0-9+/=]*\).*/\1/p' | tail -n1)"
if [ -z "$DEPS_HASH" ]; then
  printf '%s\n' "$BUILD_LOG" >&2
  echo "ERROR: could not extract npmDepsHash from nix build output" >&2
  exit 1
fi

sed -i -E "s|npmDepsHash = lib.fakeHash;|npmDepsHash = \"${DEPS_HASH}\";|" "$DEFAULT_NIX"

echo "src hash:  ${SRC_HASH}"
echo "deps hash: ${DEPS_HASH}"
echo "Done. Verify with: nix build /etc/nixos#nixosConfigurations.lecoo.pkgs.oh-my-openagent"
