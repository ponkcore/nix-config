---
name: nix-lang
description: Read the SOURCE of nixpkgs derivations and NixOS/Home-Manager option declarations, query the Nix standard library (builtins/lib via Noogle), and search a very broad set of module options (sops-nix, disko, impermanence, nixvim, microvm, nixos-hardware, ...). Use when you need to read real source or stdlib semantics, beyond what nixos-options gives.
---

# nix-lang

Replaces the former `mcp.nix` MCP server (felixdorn/mcp-nix). Complements
`nixos-options`: where that one searches packages/options, **this one reads the
actual source** (derivations and option declarations) and covers the Nix
standard library plus a much wider set of module ecosystems. Letta has no native
MCP client, so we reach the unchanged upstream server through `mcp-bridge`.

## When to use
- You need to **read the source** of a derivation or an option (to understand
  exactly what it does, defaults, or why a build behaves a certain way).
- You need **Nix language / stdlib** semantics (`builtins.*`, `lib.*`) via Noogle.
- You need options for modules beyond core NixOS/HM: sops-nix, disko,
  impermanence, nixvim, microvm, nixos-hardware, nix-nomad, mailserver, Darwin.

Priority order stays: builtin (read/grep/shell/gh) → nixos-options → **nix-lang**
→ context7-docs → web-fetch. Prefer `nixos-options` for plain "does X exist";
reach for `nix-lang` when you must read source or stdlib.

## How to call
```bash
# Search packages
mcp-bridge --server 'mcp-nix' --tool search_nixpkgs --args '{"query":"ripgrep"}'

# READ the source of a derivation
mcp-bridge --server 'mcp-nix' --tool read_derivation --args '{"attribute":"ripgrep"}'

# Search options across ecosystems (scope: nixos|home-manager|darwin|nixvim|...)
mcp-bridge --server 'mcp-nix' --tool search_options --args '{"query":"luks"}'

# READ an option's declaration (source)
mcp-bridge --server 'mcp-nix' --tool read_option_declaration --args '{"name":"services.nginx.enable"}'

# Nix stdlib (Noogle)
mcp-bridge --server 'mcp-nix' --tool search_nix_stdlib --args '{"query":"mapAttrs","limit":10}'
mcp-bridge --server 'mcp-nix' --tool help_for_stdlib_function --args '{"name":"lib.mapAttrs"}'

# Discover exact tool names + schemas
mcp-bridge --server 'mcp-nix' --list
```

If `mcp-nix` is not on PATH, fall back to `--server 'uvx --python /nix/store/.../python3.13 mcp-nix'`.
Tool argument schemas differ from upstream docs — **always verify with `--list`**
and test a call before relying on argument names. Known discrepancies:
- `search_options` takes `project` (required) + `query`, not `scope`
- `read_option_declaration` takes `project` + `name`, not `option`
- `search_nix_stdlib` requires `limit` alongside `query`

## Tools (upstream)
search_nixpkgs · read_derivation (SOURCE) · search_options (NixOS / HM / Darwin /
Nixvim / Impermanence / MicroVM / nix-nomad / mailserver / sops-nix /
nixos-hardware / disko) · list_versions · show_option_details ·
read_option_declaration (SOURCE) · find_nixpkgs_commit_with_package_version
(NixHub) · search_nix_stdlib (Noogle) · help_for_stdlib_function (Noogle).

## Data sources
search.nixos.org, ExtraNix, NuschtOS, Noogle, NixHub. No secret/API key required.

## Guardrails (from talos §7)
- Use to **read source / verify semantics**, not as the first search — that is
  `nixos-options`.
- After two consecutive failures of this server, record it in today's journal
  and continue without it (do not loop).
