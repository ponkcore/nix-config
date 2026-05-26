# obsidian.nix — Markdown knowledge base / note-taking GUI.
#
# License: Obsidian End User Agreement (unfree, allowed globally via
# nixpkgs.config.allowUnfree in modules/nixos/nix.nix). Vanilla
# nixpkgs build (Electron 39); the upstream package wraps Electron
# with the standard NixOS launcher, so NIXOS_OZONE_WL=1 (set globally
# by the Hyprland session module) makes it run native Wayland without
# any per-app flag.
#
# Vault location:
#   ~/Documents/notes/ — created on first activation, mode 0700 so
#   the directory is owner-only. Syncthing picks it up by path
#   (configured separately in modules/nixos/services.nix when needed).
#   The first-launch wizard asks the user where to put the vault;
#   pointing it at ~/Documents/notes/ keeps the layout symmetrical
#   with KeePassXC's ~/Documents/secrets/vault.kdbx.
#
# Settings — themes, community plugins, hotkeys — live INSIDE the
# vault under <vault>/.obsidian/. That directory is the user's
# mutable state and is intentionally not Home-Manager-managed: the
# same reason keepassxc.nix uses a seed-on-first-activation pattern
# instead of a HM symlink (a read-only file in the Nix store fights
# every UI write).
#
# Window rules: Obsidian is a long-session app (like Firefox), so it
# tiles by default. No entry in the Hyprland popup list. To turn it
# into a centred floating popup, add an mkPopup block with
# `class = "obsidian"; category = popup.app` in
# home/desktop/sessions/hyprland/session.nix.
{
  lib,
  pkgs,
  ...
}: {
  home.packages = [pkgs.obsidian];

  # Pre-create the notes directory so Syncthing has something to
  # mount into on first activation. 700 — owner-only — same pattern
  # as the secrets directory next to KeePassXC.
  home.activation.ensureNotesDir = lib.hm.dag.entryAfter ["writeBoundary"] ''
    install -d -m 700 "$HOME/Documents/notes"
  '';
}
