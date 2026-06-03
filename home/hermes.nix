# hermes.nix — Nous Research Hermes Desktop (Electron GUI agent).
#
# Built from source via the upstream flake's `.#desktop` package
# (nix/desktop.nix in the hermes-agent repo). The flake produces a
# fully wrapped Electron binary that points at the Nix-built `hermes`
# CLI via HERMES_DESKTOP_HERMES — no separate CLI install needed.
#
# No prebuilt Linux binary exists on CDN or GitHub Releases as of
# 2026-06-03. The website's Linux download button is disabled. The
# Nix flake is the only reliable distribution channel for Linux.
#
# Self-update is broken on packaged Linux (PR #37541) — cosmetic only;
# updates come through nix flake update + rebuild instead.
{inputs, ...}: {
  home.packages = [inputs.hermes-agent.packages.x86_64-linux.desktop];
}
