---
name: github-mcp
description: GitHub MCP server (github-mcp-server v1.0.4, official). Reached via mcp-bridge (stdio). Use for repo management, issues, PRs, code security scanning, secret protection, Actions, and more.
---

# github-mcp

GitHub's official MCP server (v1.0.4, nixpkgs). Reached
through `mcp-bridge` (Letta has no native MCP client).

## When to use

GitHub repository operations, issue/PR management, code
security scanning, secret detection, Actions workflows,
Discussions, Gists, and more.

**Token sourcing:** `GITHUB_PERSONAL_ACCESS_TOKEN` is
exported by the `talos` fish function via `gh auth token`
before launching letta. The token is NOT in agenix — `gh`
CLI is already auth'd.

**MCP evaluation principle:** For simple read-only GitHub
operations that `gh` CLI handles natively
(`gh pr list`, `gh issue view`, `gh repo view`), prefer
`gh` directly. Use this MCP server when you need:
- Code security scanning (`code_security` toolset)
- Secret protection scanning (`secret_protection` toolset)
- Structured multi-step GitHub workflows
- Operations not exposed by `gh` CLI

## Toolsets

Enabled: `default,code_security,secret_protection`

| Toolset | Scope |
|---------|-------|
| `default` | Repos, issues, PRs, Actions, Discussions, Gists, notifications, users, search |
| `code_security` | Code scanning alerts, SARIF uploads, alert status |
| `secret_protection` | Secret scanning alerts, secret scan locations |

Full toolset list (not enabled): `actions`, `copilot`,
`dependabot`, `discussions`, `gists`, `git`, `issues`,
`notifications`, `orgs`, `pages`, `pull_requests`,
`repos`, `search`, `secret_protection`, `users`,
`code_security`.

## How to call

List available tools:

```bash
mcp-bridge \
  --server 'github-mcp-server stdio --toolsets=default,code_security,secret_protection' \
  --list
```

Call a tool (example: list repos):

```bash
mcp-bridge \
  --server 'github-mcp-server stdio --toolsets=default,code_security,secret_protection' \
  --tool 'list_repos' \
  --args '{"owner":"ponkcore"}'
```

## Token environment

`GITHUB_PERSONAL_ACCESS_TOKEN` must be set in the
environment before calling `mcp-bridge`. The `talos` fish
function handles this — it calls `gh auth token` and
exports the result. If the env var is missing, the server
will fail with an authentication error.

To verify the token is set:

```bash
echo "$GITHUB_PERSONAL_ACCESS_TOKEN" | head -c 4
```

Should print a `gho_` or `github_pat_` prefix.

## Known limitations

- The server spawns a new process per `mcp-bridge` call
  (stdio transport). Cold start ~1-2s.
- `--dynamic-toolsets` is NOT used — all enabled toolsets
  are available on every call.
- For write operations (creating issues, merging PRs),
  the token must have appropriate scopes. `gh auth token`
  returns the token from the current `gh` auth session.
