# agy.nix — Antigravity CLI (agy).
# Agent runtime consumed by Open Design daemon. The daemon discovers
# agy by scanning PATH for the `agy` binary (see runtimes/defs/antigravity.ts).
# Installed via npm because nixpkgs does not package it.
# Requires nodejs_24 for npm.
{pkgs, ...}: {
  home.packages = [
    pkgs.nodejs_24
  ];
}
