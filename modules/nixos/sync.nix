# sync.nix — Syncthing for cross-device file synchronisation.
#
# Use cases on this system:
#   - ~/Documents/secrets/vault.kdbx  ← shared with Android (KeePassDX)
#   - ~/Documents                     ← shared between desktop+laptop+phone
#
# How sync works on first deploy:
#   1. After this module activates, open http://127.0.0.1:8384 (already
#      open via openDefaultPorts is left FALSE — only localhost UI).
#   2. Add the partner device by ID. Each device's ID is shown in
#      Settings → "This Device". The Android Syncthing-Fork app shows
#      the same panel.
#   3. Pair-accept on the other side, choose which folders to share.
#
# Encryption: Syncthing's wire protocol is mutually-authenticated TLS
# between paired devices — no third party sees plaintext. At-rest
# encryption is your filesystem's job (LUKS for the laptop, app-level
# for Android).
#
# username injected by lib/mkHost.nix.
{username, ...}: {
  services.syncthing = {
    enable = true;
    user = username;
    # Default data dir. Folders shared from the GUI live wherever the
    # user picks them; this is just the runtime db / certificates root.
    dataDir = "/home/${username}";
    configDir = "/home/${username}/.config/syncthing";

    # No public exposure — UI bound to localhost only. Pair via direct
    # global discovery (Syncthing's relay infrastructure) or local LAN.
    openDefaultPorts = false;
    guiAddress = "127.0.0.1:8384";
  };
}
