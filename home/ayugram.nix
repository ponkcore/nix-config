# ayugram.nix — Telegram client (Ayugram fork).
#
# No upstream Home Manager module exists, so this file is the moral
# equivalent: a thin wrapper that drops the package into the user
# environment so the rest of the flake can refer to it as "the
# Ayugram module" rather than as a stray entry in home/default.nix.
#
# Window rules and the special-workspace toggle live next to the
# Hyprland session — see home/desktop/sessions/hyprland/scripts.nix
# for the toggle and ../sessions/hyprland/session.nix for the
# `class:^(com.ayugram.desktop)$` window rules.
{pkgs, ...}: {
  home.packages = [pkgs.ayugram-desktop];
}
