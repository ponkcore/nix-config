# home/default.nix — Home Manager profile aggregator.
#
# Imported by lib/mkHost.nix into the per-host home-manager.users.<user>
# block. This file is the single entry point for the entire user
# environment; add new modules to the imports list, never to flake.nix
# directly.
#
# Three layers, mirroring the system-side dispatcher:
#   1. Always-on modules — pure shell, editor, git, fonts, …
#   2. Wayland-only modules — clipboard daemon, wlsunset, wlogout, mpv,
#      and the desktop dispatcher itself. Only imported when the host
#      has at least one entry in `desktops`. Headless hosts skip eval
#      entirely.
#   3. Compositor-specific modules — fanned out from `home/desktop/`.
{
  lib,
  username,
  desktops ? [],
  ...
}: let
  hasDesktop = desktops != [];
in {
  home.username = username;
  home.homeDirectory = "/home/${username}";
  home.stateVersion = "25.11";

  programs.home-manager.enable = true;

  imports =
    [
      # ── Layer 1: shell / editor / git / fonts — always on ─────────────
      ./env.nix
      ./git.nix
      ./fzf.nix
      ./cli.nix
      ./btop.nix
      ./cleanup.nix
      ./imaging.nix
      ./archives.nix
      ./keepassxc.nix
      ./obsidian.nix
      ./thunderbird.nix

      ./fastfetch.nix
      ./pwvucontrol.nix
      ./xdg.nix
      ./fish.nix
      ./firefox
      ./neovim.nix
      ./opencode.nix
      ./qt.nix
      ./donutbrowser.nix
      ./chromium.nix
      ./antigravity.nix

      ./direnv.nix
      ./yazi.nix
      ./ssh.nix
      ./letta.nix
    ]
    # ── Layer 2: Wayland-only modules — gated by desktops ───────────────
    ++ lib.optionals hasDesktop [
      ./clipboard.nix
      ./wlsunset.nix
      ./wlogout.nix
      ./mpv.nix
      ./ayugram.nix
      ./spotify.nix
      ./orbit.nix
      ./throne.nix
      # Desktop dispatcher — pulls in compositor-agnostic theme plus the
      # session modules selected by the host's `desktops` list.
      ./desktop
    ];
}
