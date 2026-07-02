---
name: nixos-options
description: NixOS / nixpkgs option and package lookups via the mcp-nixos server (v2.4.3). Use to verify that a package, program, or option exists before adding it to the config.
---

# nixos-options

MCP server `mcp-nixos` v2.4.3 (utensils/mcp-nixos, in nixpkgs).
Reached through `mcp-bridge` (Letta has no native MCP client).

## When to use

Before adding any `services.*` / `programs.*` / package to
`/etc/nixos`, verify the name exists. This is priority #2 in the
tool policy: builtin (read/grep/shell) → **nixos-options** →
context7-docs → web-fetch.

## Real API (verified 2026-07-02)

Two tools: `nix` (with `action` parameter) and `nix_versions`.

### Tool: `nix`

Required parameter: `action`. The action determines what other
parameters are needed.

#### action=search

Fuzzy full-text search. Returns up to 20 results. **NOT exact
match** — a search for a non-existent package returns 20 irrelevant
results. Use `action=info` for exact-match verification.

```bash
# Search packages (source=nixos, type=packages)
mcp-bridge --server 'mcp-nixos' --tool nix \
  --args '{"action":"search","query":"firefox","type":"packages","channel":"unstable"}'

# Search NixOS options (source=nixos, type=options)
mcp-bridge --server 'mcp-nixos' --tool nix \
  --args '{"action":"search","query":"nginx","type":"options","channel":"unstable"}'

# Search programs (source=nixos, type=programs)
mcp-bridge --server 'mcp-nixos' --tool nix \
  --args '{"action":"search","query":"waybar","type":"programs","channel":"unstable"}'
```

For `source=nixos`, `type` must be one of: `packages`, `options`,
`programs`, `flakes`.

Other sources do NOT take `type` — they take `source` directly:

```bash
# Nixvim options
mcp-bridge --server 'mcp-nixos' --tool nix \
  --args '{"action":"search","query":"sway","source":"nixvim"}'

# NixOS Wiki
mcp-bridge --server 'mcp-nixos' --tool nix \
  --args '{"action":"search","query":"nix","source":"wiki"}'

# nix.dev documentation
mcp-bridge --server 'mcp-nixos' --tool nix \
  --args '{"action":"search","query":"flake","source":"nix-dev"}'

# Noogle (Nix stdlib functions)
mcp-bridge --server 'mcp-nixos' --tool nix \
  --args '{"action":"search","query":"builtins","source":"noogle"}'

# NixHub (package metadata)
mcp-bridge --server 'mcp-nixos' --tool nix \
  --args '{"action":"search","query":"ruby","source":"nixhub"}'

# FlakeHub
mcp-bridge --server 'mcp-nixos' --tool nix \
  --args '{"action":"search","query":"hyprland","source":"flakehub"}'
```

#### action=info

Exact match. Returns NOT_FOUND if the name does not exist. **This
is the reliable way to verify that a package or option exists.**

```bash
# Package info
mcp-bridge --server 'mcp-nixos' --tool nix \
  --args '{"action":"info","query":"firefox","type":"package","channel":"unstable"}'

# NixOS option info
mcp-bridge --server 'mcp-nixos' --tool nix \
  --args '{"action":"info","query":"services.nginx.enable","type":"option","channel":"unstable"}'
```

For non-nixos sources, use `source` instead of `type`:

```bash
# darwin option info
mcp-bridge --server 'mcp-nixos' --tool nix \
  --args '{"action":"info","query":"programs.git.enable","source":"darwin"}'
```

#### action=stats

```bash
# NixOS channel statistics
mcp-bridge --server 'mcp-nixos' --tool nix \
  --args '{"action":"stats","source":"nixos","channel":"unstable"}'

# darwin statistics
mcp-bridge --server 'mcp-nixos' --tool nix \
  --args '{"action":"stats","source":"darwin"}'
```

#### action=channels

Lists all indexed channels with document counts and branch HEADs.

```bash
mcp-bridge --server 'mcp-nixos' --tool nix \
  --args '{"action":"channels"}'
```

#### action=browse

Prefix browsing for noogle and nixvim only.

```bash
mcp-bridge --server 'mcp-nixos' --tool nix \
  --args '{"action":"browse","source":"noogle","query":"lib"}'
```

#### action=store

Read a file from the Nix store by absolute path.

```bash
mcp-bridge --server 'mcp-nixos' --tool nix \
  --args '{"action":"store","type":"read","query":"/nix/store/xxxx-source/path/file.py"}'
```

#### action=flake-inputs

Read flake inputs from a flake directory.

```bash
mcp-bridge --server 'mcp-nixos' --tool nix \
  --args '{"action":"flake-inputs","type":"read","query":"nixpkgs:flake.nix"}'
```

#### action=cache

Check binary cache status for a package.

```bash
mcp-bridge --server 'mcp-nixos' --tool nix \
  --args '{"action":"cache","query":"firefox"}'
```

### Tool: nix_versions

Package version history from NixHub.io with nixpkgs commit hashes.

```bash
mcp-bridge --server 'mcp-nixos' --tool nix_versions \
  --args '{"package":"firefox","limit":5}'
```

### Discover tools

```bash
mcp-bridge --server 'mcp-nixos' --list
```

## Channels

Available channels: `unstable`, `stable`, `beta`, `25.11`.

**26.05 is NOT indexed.** Use `unstable` as a proxy — nixos-26.05
tracks close to unstable. Always cross-check critical options with
local `nix eval` or source when the channel matters.

## Known limitations (verified 2026-07-02)

### Broken sources

| Source | Status | Root cause |
|--------|--------|------------|
| `home-manager` | BROKEN | HM docs migrated from DocBook to mdBook. `options.xhtml` is now a redirect page — `parse_html_options` finds no `<dt>` elements, returns empty. Upstream v2.4.3 not adapted. |
| `flakes` | BROKEN | `FLAKE_INDEX = "latest-44-group-manual"` — search.nixos.org reindexed, 404. |

### Channel 26.05 missing

`BASE_CHANNELS` in config.py hardcodes only `25.05` and `25.11`.
Channel `26.05` is rejected with "Invalid channel". Use `unstable`.

### Search is fuzzy, not exact

`action=search` does full-text matching. A query for
`this-package-does-not-exist-xyz123` returns 20 irrelevant results.
**Never use `search` to verify existence — use `action=info`**,
which does exact match and returns NOT_FOUND for unknown names.

### Index freshness

The search index may lag behind the local nixpkgs. Example:
firefox shows 149.0.2 in the index vs 152.0.2 in local `nix eval`.
For version-sensitive decisions, always cross-check with
`nix eval nixpkgs#<attr>.version` locally.

### Source naming

Use hyphens, not underscores: `home-manager` (not
`home_manager`), `nix-dev` (not `nix_dev`).

## Guardrails (from talos persona)

- This is the FIRST place to check nixpkgs/NixOS facts — before
  context7 or fetch, before any web search, before guessing.
- For Home Manager option verification: use `nix eval` locally or
  `grep` the HM source, since the `home-manager` source is broken.
- After two consecutive failures of this server, record it in
  today's journal and continue without it (do not loop).
