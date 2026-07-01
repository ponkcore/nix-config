---
name: omniroute-mcp
description: Access the VPS MCP proxy via mcp-bridge over remote HTTP/SSE. Filtered to web_search + web_fetch only. Use when web search or page fetch is needed and nixos-options/nix-lang/context7-docs/web-fetch cannot answer.
---

# omniroute-mcp

Connects to the VPS MCP proxy on `mcp.infinitycore.space` that
filters the upstream OmniRoute MCP server to exactly two tools:
`web_search` and `web_fetch`. The real OmniRoute API key lives on
the VPS; laptop clients authenticate to the proxy with `X-Proxy-Key`.

- URL: `https://mcp.infinitycore.space:8443/omp/sse`
- Auth: `X-Proxy-Key` header from `OMP_PROXY_KEY` env var
- Transport: Streamable HTTP (SSE) through `mcp-bridge --url`
- Available tools: `web_search`, `web_fetch` (proxy-filtered)

The proxy key comes from agenix (`/run/agenix/tokens`) and is
exported into the environment. Never put it on the command line
or into `--args`.

## Timing (cold-start, SSE)

The remote SSE endpoint can take **up to 75 s** on the first call
in a session (TLS handshake + MCP initialize + tool discovery).
Every call after that in the same session completes in ~1–5 s.

**Rules:**
- **Never run OmniRoute SSE calls in parallel.** `mcp-bridge --url
  ... --transport sse` creates a fresh MCP/SSE session per process.
  Parallel cold starts stampede the operator endpoint and locally
  pile up long-running bridge processes. Run one OmniRoute call at
  a time; if multiple searches are needed, issue them sequentially.
- **Always use `--timeout 90`** for the first call in a session
  (cold SSE start). Subsequent calls can use `--timeout 60`.
- The outer `bash` `timeout` must be **at least 15 s larger** than
  the inner `--timeout`.
- `_queue.Empty` from `mcp-bridge` means the bridge waited for an
  MCP response until timeout; treat it as a timeout, not as a
  search result.
- Two consecutive timeouts (including `_queue.Empty`, not HTTP/auth
  errors) → record in today's journal and stop trying. The server
  is likely overloaded, down, or network-partitioned.
- Cold start is once per MCP session. If `--list` succeeds,
  subsequent tool calls in the same agent turn are already warm —
  but still not parallel.

## How to call

List tools:

```bash
mcp-bridge \
  --url 'https://mcp.infinitycore.space:8443/omp/sse' \
  --transport sse \
  --header-env 'X-Proxy-Key=OMP_PROXY_KEY' \
  --timeout 90 \
  --list
```

Call web_search:

```bash
mcp-bridge \
  --url 'https://mcp.infinitycore.space:8443/omp/sse' \
  --transport sse \
  --header-env 'X-Proxy-Key=OMP_PROXY_KEY' \
  --timeout 90 \
  --tool 'web_search' \
  --args '{"query": "NixOS sing-box TUN mode configuration"}'
```

Call web_fetch:

```bash
mcp-bridge \
  --url 'https://mcp.infinitycore.space:8443/omp/sse' \
  --transport sse \
  --header-env 'X-Proxy-Key=OMP_PROXY_KEY' \
  --timeout 90 \
  --tool 'web_fetch' \
  --args '{"url": "https://example.com/page"}'
```

## Available tools

Only two tools are exposed by the proxy:

| Tool | Description |
|------|-------------|
| `web_search` | Web search via OmniRoute's search gateway (Serper, Brave, Perplexity, Exa, Tavily with failover). Returns titles, URLs, snippets. |
| `web_fetch` | Fetch and extract content from a URL (Firecrawl, Jina Reader, Tavily with failover). Returns markdown/HTML/links. |

No other tools are available. The proxy filters out all OmniRoute
routing, combo, quota, admin, and diagnostic tools.

## Priority

This skill is the last resort in the tool chain:
builtin → nixos-options → nix-lang → context7-docs → web-fetch
(local `fetch.py`) → **omniroute-mcp** (remote search/fetch) →
delegate/ask.

Use `web-fetch` (local `fetch.py`) first for known URLs — it is
faster (no SSE cold start) and has no API key dependency. Use
`omniroute-mcp` when you need **search** (no concrete URL) or when
`fetch.py` fails (JS-rendered pages, anti-bot blocks).

## Architecture

Full proxy architecture, auth, transport pitfalls, and tool naming
conventions: see
[reference/mcp-proxy-architecture.md](../../../../../Documents/talos-brain/../../../.letta/lc-local-backend/memfs/agent-local-686d5667-5fc0-45c2-ab97-f3e984b22a27/memory/reference/mcp-proxy-architecture.md)
in talos memory.
