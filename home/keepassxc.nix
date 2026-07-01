# keepassxc.nix — local password manager.
#
# Vault location: ~/Documents/secrets/vault.kdbx (synchronised between
# devices via Syncthing — configured in modules/nixos/services.nix).
# Android setup: docs/handbook.md §Cross-device sync.
#
# Why a seed-on-first-activation pattern instead of programs.keepassxc:
#   The Home Manager module symlinks ~/.config/keepassxc/keepassxc.ini
#   into the Nix store as a read-only file. KeePassXC tries to write
#   the ini on every launch (recent files, window geometry, plugin
#   toggles) and pops a modal "Access error for config file" QMessage-
#   Box because of the read-only target. The HM module has no
#   "mutable" mode for this file.
#
# Seed pattern (see decisions/0011-keepassxc-seed-not-symlink.md):
#   * declare the intended starting values in Nix (single source of
#     truth, propagates to new hosts on first nixos-rebuild);
#   * write them as a regular mutable file only if the user does not
#     already have one — KeePassXC then owns the file from there on
#     and freely persists its own UI state;
#   * to roll out a Nix-side change to an already-seeded host: remove
#     the ini and rebuild.
#
# Browser integration — install the keepassxc-browser extension in
# Firefox/Chromium/Brave/Floorp/Vivaldi, then enable in
# Settings → Browser Integration. UpdateBinaryPath = false in the seed
# tells KeePassXC not to fight Home Manager over native-messaging
# manifest paths.
{
  lib,
  pkgs,
  ...
}: let
  iniFormat = pkgs.formats.ini {};

  keepassxcWrapped = pkgs.symlinkJoin {
    name = "keepassxc-wrapped";
    paths = [pkgs.keepassxc];
    nativeBuildInputs = [pkgs.makeWrapper];
    postBuild = ''
      rm $out/bin/keepassxc
      makeWrapper ${pkgs.keepassxc}/bin/keepassxc $out/bin/keepassxc \
        --set-default QT_STYLE_OVERRIDE kvantum \
        --unset QT_QPA_PLATFORMTHEME
    '';
  };

  seedFile = iniFormat.generate "keepassxc.ini" {
    General = {
      # Lock workspace after 5 minutes of inactivity.
      LockDatabaseIdle = true;
      LockDatabaseIdleSeconds = 300;
      MinimizeOnClose = true;
      MinimizeOnStartup = false;
      # Updates only via flake — no need for KeePassXC to phone home.
      CheckForUpdates = false;
    };
    Browser = {
      # Browser integration on by default — the Firefox profile
      # ships keepassxc-browser + the native-messaging manifest via
      # programs.firefox.nativeMessagingHosts (see
      # home/firefox/default.nix). On already-seeded hosts this
      # value is *not* re-applied; toggle in Settings → Browser
      # Integration once after the rebuild.
      Enabled = true;
      # HM owns the native-messaging manifests; tell KeePassXC NOT to
      # rewrite them at startup (otherwise it conflicts with the
      # nix-store paths HM symlinks in).
      UpdateBinaryPath = false;
    };
    GUI = {
      ApplicationTheme = "dark";
      MinimizeToTray = true;
      ShowTrayIcon = true;
      TrayIconAppearance = "monochrome-dark";
      MinimizeOnOpenUrl = false;
    };
  };
in {
  home.packages = [
    # ── KeePassXC wrapper: neutralise Qt6 platform theme for Qt5 app ─
    # KeePassXC is Qt5. The global session sets QT_QPA_PLATFORMTHEME=qt6ct
    # (to serve Qt6 apps like Throne). Qt5 cannot load the qt6ct plugin,
    # which makes the platformtheme fall back on Qt5 defaults (Fusion)
    # most of the time — but single-instance D-Bus restore / startup timing
    # makes Kvantum styling flaky. This per-app wrapper keeps the
    # well-tested Hyprland launch env intact for everything else while
    # giving KeePassXC a predictable Qt5 environment every time.
    keepassxcWrapped
  ];

  # Pre-create the secrets directory so Syncthing has something to mount
  # into on first activation. 700 — owner-only — defends the .kdbx.
  home.activation.ensureSecretsDir = lib.hm.dag.entryAfter ["writeBoundary"] ''
    install -d -m 700 "$HOME/Documents/secrets"
  '';

  # Seed ~/.config/keepassxc/keepassxc.ini on first activation only.
  # The "[ ! -e ]" guard means subsequent rebuilds leave the live file
  # untouched, so KeePassXC's own state (recent files, geometry) is
  # preserved across rebuilds. To re-seed: rm the file, rebuild.
  home.activation.keepassxcSeed = lib.hm.dag.entryAfter ["writeBoundary"] ''
    ini="$HOME/.config/keepassxc/keepassxc.ini"
    if [ ! -e "$ini" ]; then
      install -D -m600 ${seedFile} "$ini"
    fi

    # Keep the already-mutable live config deterministic for the one UI
    # value that caused regressions: KeePassXC defaults GUI/ApplicationTheme
    # to "auto", which can resolve to light depending on portal/system theme
    # state at startup. Preserve all other runtime state; do not rewrite the
    # whole ini because it may contain KeeShare key material.
    if [ -e "$ini" ] && ! ${pkgs.gnugrep}/bin/grep -q '^ApplicationTheme=dark$' "$ini"; then
      ${pkgs.gawk}/bin/awk '
        BEGIN { in_gui = 0; done = 0 }
        /^\[GUI\]$/ { print; in_gui = 1; next }
        /^\[/ && in_gui && !done { print "ApplicationTheme=dark"; done = 1; in_gui = 0 }
        in_gui && /^ApplicationTheme=/ { if (!done) { print "ApplicationTheme=dark"; done = 1 }; next }
        { print }
        END { if (in_gui && !done) print "ApplicationTheme=dark" }
      ' "$ini" > "$ini.tmp"
      install -m600 "$ini.tmp" "$ini"
      rm -f "$ini.tmp"
    fi
  '';
}
