---
name: context7-docs
description: Fetch up-to-date, version-specific documentation and code examples for libraries/frameworks via Context7. Use to resolve a library name to its Context7 ID and pull focused docs before writing code against an external library.
---

# context7-docs

Replaces the former `context7` MCP server (Upstash @upstash/context7-mcp). It
provides current, version-specific library documentation and code snippets.
Letta has no native MCP client, so we reach the unchanged upstream server
through `mcp-bridge`, running context7-mcp in **stdio** transport
(the binary wrapper already passes `--transport stdio`).

The API key is provided via the environment (`CONTEXT7_API_KEY`, from agenix —
same pattern as `OMNIROUTE_API_KEY`); `mcp-bridge` inherits the environment, so
no key ever appears on the command line.

## When to use
Before writing or debugging code against an external library/framework where
exact, current API details matter (function signatures, config keys, examples).
Priority: builtin → nixos-options → nix-lang → **context7-docs** → web-fetch.
For Nix/NixOS facts use the nix skills first; context7 is for general
programming libraries.

## How to call
Two-step: resolve the library name to a Context7 ID, then fetch docs.

```bash
# 1) Resolve a library name -> Context7-compatible library ID
mcp-bridge --server 'context7-mcp' \
  --tool resolve-library-id --args '{"libraryName":"fastapi","query":"fastapi"}'

# 2) Fetch focused docs for that ID
mcp-bridge --server 'context7-mcp' \
  --tool query-docs \
  --args '{"context7CompatibleLibraryID":"/fastapi/fastapi","topic":"dependencies","tokens":4000}'

# Discover exact tool names + argument keys
mcp-bridge --server 'context7-mcp' --list
```

If `context7-mcp` is not on PATH, fall back to
`--server 'npx -y @upstash/context7-mcp --transport stdio'`.
`CONTEXT7_API_KEY` must be present in the environment (it is, via the talos
wrapper). `resolve-library-id` requires both `libraryName` and `query` (pass
the same value for both). Always confirm exact tool names/args with `--list`
first if a call is rejected — upstream occasionally renames tools.

## Tools (upstream)
- `resolve-library-id(libraryName, query)` → best-matching Context7 library ID(s).
- `query-docs(context7CompatibleLibraryID[, topic][, tokens])` → docs.

## Guardrails (from talos §7)
- Never put secrets, tokens, internal hostnames, or lecoo-specific details into
  Context7 queries — queries leave the machine.
- Resolve the ID first; do not guess a `context7CompatibleLibraryID`.
- After two consecutive failures, record it in today's journal and continue
  without it (do not loop).
