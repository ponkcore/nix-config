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
#   ~/Documents/obsidian/ — container for multiple Obsidian vaults
#   (one project per subdir). The first vault, "brain", lives at
#   ~/Documents/obsidian/brain/ and is the one synced to the VPS via
#   Syncthing (see modules/nixos/sync.nix folder "brain"). Both
#   directories are created on first activation, mode 0700 so they
#   are owner-only. The first-launch wizard asks where to put the
#   vault; point it at ~/Documents/obsidian/brain. Layout is
#   symmetrical with KeePassXC's ~/Documents/secrets/vault.kdbx.
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

  # Pre-create the vault container and the first vault ("brain") so
  # Syncthing has something to mount into on first activation. 700 —
  # owner-only — same pattern as the secrets directory next to
  # KeePassXC.
  # install -d does not chmod existing directories; chmod runs after
  # so manually-created directories get normalised to 0700 too.
  home.activation.ensureObsidianDirs = lib.hm.dag.entryAfter ["writeBoundary"] ''
    install -d -m 700 "$HOME/Documents/obsidian"
    install -d -m 700 "$HOME/Documents/obsidian/brain"
    chmod 700 "$HOME/Documents/obsidian" "$HOME/Documents/obsidian/brain"
  '';

  # Syncthing never syncs .stignore itself, so seed/repair the local
  # ignore policy on each host. The file stays mutable; this only fixes
  # the known-bad `.git/` pattern, which ignores contents but not the
  # directory node and leaves a permanent pending delete for `.git`.
  home.activation.ensureObsidianBrainStignore = lib.hm.dag.entryAfter ["ensureObsidianDirs"] ''
        stignore="$HOME/Documents/obsidian/brain/.stignore"

        if [ ! -e "$stignore" ]; then
          cat >"$stignore" <<'EOF'
    // Syncthing ignore patterns for the Obsidian "brain" vault.

    // Per-device Obsidian UI state — rewritten on every focus/blur.
    .obsidian/workspace*
    .obsidian/cache/
    .obsidian/plugins/*/cache/
    .obsidian/plugins/*/data.json.tmp
    .obsidian/workspace-mobile.json

    // Editor / OS clutter.
    .DS_Store
    Thumbs.db
    *.swp
    *~

    // Obsidian Git keeps history inside the vault. Syncthing must ignore
    // the directory node itself, so this pattern is intentionally slashless.
    .git
    .gitignore
    .gitattributes

    // Trash — local-only, safe to skip.
    .trash/
    EOF
          chmod 600 "$stignore"
        elif ${pkgs.gnused}/bin/sed -n '/^\.git\/$/p' "$stignore" | ${pkgs.gnugrep}/bin/grep -q .; then
          ${pkgs.gnused}/bin/sed -i 's#^\.git/$#.git#' "$stignore"
        fi
  '';
}
