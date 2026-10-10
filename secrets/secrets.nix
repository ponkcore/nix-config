# secrets.nix — agenix authorisation map.
#
# Lists which public keys are allowed to decrypt each secret. agenix
# uses this file ONLY when running `agenix -e <file>.age` to encrypt
# a new value or re-encrypt after a key rotation. The decryption at
# system activation time uses the host's /etc/ssh/ssh_host_ed25519_key
# directly, not this file.
#
# Adding a new host: append its `ssh_host_ed25519_key.pub` value here
# under a descriptive `let` binding, add it to the publicKeys list of
# every secret the host needs, then re-encrypt with `agenix -r`.
#
# Adding a new user-editor: append the user's `~/.ssh/id_ed25519.pub`
# the same way, then re-encrypt. age supports SSH ed25519 keys natively.
#
# To get a host key from a remote machine without logging in:
#   ssh-keyscan -t ed25519 <host>
let
  # ── Hosts ────────────────────────────────────────────────────────────
  lecoo = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKDDIhZMuFCLc6SEN7uGW0S9fsDxVRa/Xg3VtiBLuUhU root@nixos";

  hosts = [lecoo];

  # ── Users ────────────────────────────────────────────────────────────
  ponkcore = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKt6VvFVWoIexrL2Kh36gMEPfa5u3RaoI3vYebUHk+1A ponkcore@lecoo";

  users = [ponkcore];

  all = hosts ++ users;
in {
  # tokens.age — bundle of all third-party API tokens consumed by user-
  # space agent tooling (letta runtime, opencode runtime, opencode MCP clients).
  # Decrypted at activation time into /run/agenix/tokens (chmod 400,
  # owner=oonishi). Read by home/letta.nix at runtime and home/opencode.nix
  # when rendering its config file.
  #
  # Current contents (7 keys, verified against /run/agenix/tokens 2026-10-10):
  #   OMNIROUTE_API_KEY     — omniroute provider apiKey (opencode/omp/letta)
  #   CLIPROXY_API_KEY      — clip provider apiKey (opencode/omp/letta); Gemini
  #                           via ClipProxy on the VPS
  #   LAZYWEB_MCP_TOKEN     — opencode lazyweb MCP server (Bearer header)
  #   CONTEXT7_API_KEY      — context7 MCP server (X-Context7-API-Key header)
  #   OMP_PROXY_KEY         — VPS MCP proxy tool-filter (X-Proxy-Key header)
  #   OMP_GATE_KEY          — VPS MCP Caddy gate for /omp/* (X-API-Key header)
  #   HEXSTRIKE_API_KEY     — VPS MCP Caddy gate for /hex/* (X-API-Key header)
  "tokens.age".publicKeys = all;
}
