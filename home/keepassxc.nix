# keepassxc.nix — local password manager.
#
# Vault location: ~/Documents/secrets/vault.kdbx (synchronised between
# devices via Syncthing — configured in modules/nixos/services.nix).
# Android setup: docs/handbook.md §Cross-device sync.
#
# Browser integration: HM auto-registers native-messaging manifests for
# Firefox/Chromium/Brave/Floorp/Vivaldi when programs.keepassxc.enable
# is true. To finish pairing:
#   1. Install the keepassxc-browser extension in your browser.
#   2. KeePassXC → Settings → Browser Integration → tick the browser.
#   3. Click "Connect" in the extension and accept the prompt in KeePassXC.
{lib, ...}: {
  programs.keepassxc = {
    enable = true;

    settings = {
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
        # User toggles this on after pairing the browser extension. Pre-
        # enabling it without an extension just produces noise on launch.
        Enabled = false;
        # HM owns the native-messaging manifests; tell KeePassXC NOT to
        # rewrite them at startup (otherwise it conflicts with the nix-store
        # paths HM symlinks in).
        UpdateBinaryPath = false;
      };
      GUI = {
        MinimizeToTray = true;
        ShowTrayIcon = true;
        TrayIconAppearance = "monochrome-dark";
        # Do not pop the unlock dialog at start — open from tray on demand.
        MinimizeOnOpenUrl = false;
      };
    };

    # Don't autostart — keepassxc is opened on demand. Trayed apps that
    # autostart are a battery and noise overhead on a laptop.
    autostart = false;
  };

  # Pre-create the secrets directory so Syncthing has something to mount
  # into on first activation. 700 — owner-only — defends the .kdbx.
  home.activation.ensureSecretsDir = lib.hm.dag.entryAfter ["writeBoundary"] ''
    install -d -m 700 "$HOME/Documents/secrets"
  '';
}
