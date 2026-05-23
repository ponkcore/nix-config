# keepassxc.nix — local password manager.
#
# Vault location: ~/Documents/secrets/vault.kdbx (synchronised between
# devices via Syncthing — configured in modules/nixos/services.nix).
# Android setup: docs/handbook.md §Cross-device sync.
#
# We install KeePassXC as a plain package rather than via the
# `programs.keepassxc` Home Manager module: the module symlinks
# ~/.config/keepassxc/keepassxc.ini into the Nix store (read-only),
# which makes KeePassXC pop a modal "Access error for config file"
# dialog on every launch and prevents it from persisting GUI state
# (recent databases, window geometry, plugin toggles). The settings
# we used to declare here (auto-lock 5 min, tray-only, etc.) are set
# once interactively in Settings → General/Security/GUI; they survive
# nixos-rebuild because the ini is now a regular mutable file.
#
# Browser integration — install the keepassxc-browser extension in
# Firefox/Chromium/Brave/Floorp/Vivaldi, then enable in
# Settings → Browser Integration. KeePassXC will write the native-
# messaging manifest itself.
{
  lib,
  pkgs,
  ...
}: {
  home.packages = [pkgs.keepassxc];

  # Pre-create the secrets directory so Syncthing has something to mount
  # into on first activation. 700 — owner-only — defends the .kdbx.
  home.activation.ensureSecretsDir = lib.hm.dag.entryAfter ["writeBoundary"] ''
    install -d -m 700 "$HOME/Documents/secrets"
  '';
}
