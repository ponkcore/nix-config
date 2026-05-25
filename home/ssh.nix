# ssh.nix — OpenSSH client configuration.
#
# Catalogue layout: this module ships only the *structure* and
# defensive defaults. The actual host catalogue (hostnames, users,
# port overrides, ProxyJump, IdentityFile) lives in a private,
# git-excluded file at:
#
#     ~/Documents/ssh-private/config
#
# That file is plain ssh_config(5) syntax and is pulled in via
# `programs.ssh.includes`. The directory carries a `.talos-skip`
# marker so the talos agent never scans it without an explicit
# `read <path>` request.
#
# Why a separate file rather than `programs.ssh.matchBlocks` in Nix:
# the nix-config repo is public (`ponkcore/nix-config` on GitHub).
# Encoding real hostnames/IPs/users in a publicly-indexed file would
# (a) advertise the operator's infra topology to scrapers and (b)
# give scan bots a curated list of live ssh endpoints rather than
# having to bruteforce 0.0.0.0/0:22. Keeping the catalogue out of
# git costs declarative purity but the trade is worth it for a
# public repo.
#
# Defaults set here apply to every Host stanza unless overridden:
#
#   * forwardAgent = false  — agent forwarding is off by default;
#     enable per-host only when needed (it lets the remote host's
#     root impersonate your keys against any reachable third host
#     for the duration of the session).
#   * addKeysToAgent = "yes" — first successful key-unlock per
#     boot caches the key in the running agent, no re-prompt for
#     subsequent connections in the same session.
#   * serverAliveInterval = 60 — silent keepalive every minute,
#     so NAT timeouts (typically 5–15 min on home routers) and
#     Wi-Fi micro-disconnects don't kill the session before the
#     remote multiplexer (tmux on the server) can save state.
#   * serverAliveCountMax = 3 — three failed keepalives in a row
#     drop the session; total tolerated outage ≈ 3 min.
#   * hashKnownHosts = true — entries in ~/.ssh/known_hosts are
#     hashed so a stolen file doesn't leak the host inventory.
{pkgs, ...}: {
  # sshs — TUI fuzzy launcher over `~/.ssh/config`. Reads the file
  # produced by programs.ssh below (plus the private include) and
  # presents an fzf-style searchable list of hosts; on selection it
  # execs `ssh <host>`. Pure consumer of the config file — no
  # state of its own, no agent, no daemon.
  home.packages = [pkgs.sshs];

  programs.ssh = {
    enable = true;

    # Pull the private host catalogue into ~/.ssh/config without
    # exposing it to git. The file may not exist on a fresh
    # checkout — OpenSSH treats a missing Include target as a
    # warning, not an error.
    includes = [
      "~/Documents/ssh-private/config"
    ];

    matchBlocks = {
      "*" = {
        forwardAgent = false;
        addKeysToAgent = "yes";
        serverAliveInterval = 60;
        serverAliveCountMax = 3;
        hashKnownHosts = true;
      };
    };
  };
}
