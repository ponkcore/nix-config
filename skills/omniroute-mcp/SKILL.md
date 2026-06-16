---
name: omniroute-mcp
description: Access the operator-hosted OmniRoute MCP endpoint via mcp-bridge over remote HTTP/SSE. Use when the user asks for OmniRoute MCP tools or wants to inspect/adjust the OmniRoute MCP tool surface.
---

# omniroute-mcp

Connects to the operator-hosted OmniRoute MCP endpoint:

- URL: `https://mcp.infinitycore.space:8443/sse`
- Auth: `X-API-Key` header from `OMNIROUTE_MCP_API_KEY`
- Transport: remote HTTP/SSE through `mcp-bridge --url`

The API key comes from agenix (`/run/agenix/tokens`) and is exported by the
`talos` fish wrapper. Never put it on the command line or into `--args`.

## Timing (cold-start, SSE)

The remote SSE endpoint can take **up to 75 s** on the first call in a session
(TLS handshake + MCP initialize + tool discovery). Every call after that in the
same session completes in ~1–5 s.

**Rules:**
- **Never run OmniRoute SSE calls in parallel.** `mcp-bridge --url ... --transport sse`
  creates a fresh MCP/SSE session per process. Parallel cold starts stampede the
  operator endpoint and locally pile up long-running bridge processes. On the
  OmniRoute server this can corrupt/degrade in-memory SSE/session + connection
  pool state: stuck sessions stay resident, later Fireworks requests hang until
  120 s timeouts, retries cascade into 502s, and a server restart is needed to
  clear the slate. Run one OmniRoute call at a time; if multiple searches are
  needed, issue them sequentially.
- **Always use `--timeout 75`** (not the default 60) for the first call. For
  `omniroute_web_search` queries (which may take up to 10 s internally), use
  `--timeout 90`.
- The outer `bash` `timeout` must be **at least 15 s larger** than the inner
  `--timeout`. If you wrap the call in `timeout <N> bash -c '...'`, make N
  large enough.
- `_queue.Empty` from `mcp-bridge` means the bridge waited for an MCP response
  until timeout; treat it as a timeout, not as a search result.
- Two consecutive timeouts (including `_queue.Empty`, not HTTP/auth errors) →
  record in today's journal and stop trying. The server is likely overloaded,
  down, or network-partitioned.
- Cold start is once per MCP session. If `--list` succeeds, subsequent tool
  calls in the same agent turn are already warm — but still not parallel.

## How to call

List tools:

```bash
mcp-bridge \
  --url 'https://mcp.infinitycore.space:8443/sse' \
  --transport sse \
  --header-env 'X-API-Key=OMNIROUTE_MCP_API_KEY' \
  --timeout 90 \
  --list
```

Call a tool:

```bash
mcp-bridge \
  --url 'https://mcp.infinitycore.space:8443/sse' \
  --transport sse \
  --header-env 'X-API-Key=OMNIROUTE_MCP_API_KEY' \
  --timeout 90 \
  --tool '<tool_name>' \
  --args '{"key":"value"}'
```

## Default safe surface

Only one OmniRoute MCP tool is allowed for talos:

- `omniroute_web_search`

Do not call any other tool from this MCP endpoint. This includes read-only
OmniRoute diagnostics/catalog tools, runtime routing changes, plugin management,
cache operations, memory operations, Notion, Obsidian, compression, oneproxy,
skills, and gamification tools. If the user asks for another OmniRoute MCP tool,
first explain that the local policy currently allows only `omniroute_web_search`
and ask for an explicit temporary exception.

## Tool-surface maintenance

When the user wants to adjust the list of tools exposed by this MCP server:

1. List current tools with `--list`.
2. For OpenCode, edit the top-level `tools = { <tool-name> = false; };` map in
   `/etc/nixos/home/opencode.nix`; OpenCode's `mcp.<name>` schema has no
   per-server include/exclude allowlist.
3. For talos, update this skill's safe/blocked guidance. The actual server still
   exposes all tools; the skill is the policy layer.
4. Do not guess server-side configuration. If the MCP exposes an admin/config
   tool, call it only with explicit user-approved arguments. If not, report that
   the exposed tool list must be changed server-side on `mcp.infinitycore.space`.

## Priority

This skill is not part of the default Nix documentation chain. Use it only for
OmniRoute MCP-specific operations or when the user explicitly asks for it.
