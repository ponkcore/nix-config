---
name: nixos-options
description: Authoritative, real-time NixOS / nixpkgs / Home Manager / flake / binary-cache lookups via the mcp-nixos server. Sole source of truth for whether a package, program, or option exists before adding it to the config.
---

# nixos-options

Replaces the former `mcp.nixos` MCP server (utensils/mcp-nixos). It is the
**sole source of truth** for nixpkgs packages, NixOS / Home Manager / nix-darwin
options, flakes, NixHub version history, and binary-cache status. Letta has no
native MCP client, so we reach the unchanged upstream server through the
`mcp-bridge` helper.

## When to use
Before adding any `services.*` / `programs.*` / package to `/etc/nixos`, verify
the name exists. Do **not** guess option or package names. This is priority #2
in the tool policy: builtin (read/grep/shell/gh) → **nixos** → context7 → fetch.

## How to call
`mcp-bridge` runs the server for one tool call and prints the result:

```bash
# Search packages
mcp-bridge --server 'mcp-nixos' --tool nixos_search \
  --args '{"query":"firefox","type":"packages","channel":"unstable"}'

# Get option details
mcp-bridge --server 'mcp-nixos' --tool nixos_info \
  --args '{"name":"services.nginx.enable","type":"option"}'

# Home Manager option search
mcp-bridge --server 'mcp-nixos' --tool home_manager_search --args '{"query":"git.enable"}'

# Package version history (with nixpkgs commit hashes)
mcp-bridge --server 'mcp-nixos' --tool nixhub_package_versions --args '{"package":"ruby","limit":10}'

# Discover every tool
mcp-bridge --server 'mcp-nixos' --list
```

If `mcp-nixos` is not on PATH, fall back to `--server 'uvx mcp-nixos'`.

## Tools (upstream)
- `nixos_search(query, type[, channel])` — type ∈ packages | options | programs
- `nixos_info(name, type[, channel])` — detailed package/option info
- `nixos_stats(channel)`, `nixos_channels()`
- `nixos_flakes_search(query)`, `nixos_flakes_stats()`
- `nixhub_package_versions(package[, limit])`, `nixhub_find_version(package, version)`
- `home_manager_search/info/stats/list_options/options_by_prefix`
- `darwin_*` — macOS only; **not relevant on lecoo (NixOS)**, ignore.

## Data sources
search.nixos.org backend, NixHub.io, FlakeHub, cache.nixos.org, NuschtOS,
wiki.nixos.org, nix.dev, local /nix/store. No secret/API key required.

## Guardrails (from talos §7)
- This is the FIRST place to check nixpkgs/NixOS/Home Manager facts — before
  context7 or fetch, before any web search, before guessing.
- The companion `nix-lang` skill (felixdorn/mcp-nix) additionally reads
  derivation / option **source code** and the Nix stdlib (Noogle); use it when
  you need to read `read_derivation` / `read_option_declaration` / stdlib.
- After two consecutive failures of this server, record it in today's journal
  and continue without it (do not loop).
