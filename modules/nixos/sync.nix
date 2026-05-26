# sync.nix — Syncthing for cross-device file synchronisation.
#
# Use cases on this system:
#   - ~/Documents/secrets/vault.kdbx          ← Android (KeePassDX)
#   - ~/Documents/obsidian/brain              ← VPS (Obsidian vault)
#
# Pairing model:
#   The folder/device topology is declared here (services.syncthing.
#   settings) so the Nix expression is the single source of truth and
#   wins over any GUI edits (overrideDevices / overrideFolders = true).
#   The GUI on http://127.0.0.1:8384 is read-mostly: introspection,
#   conflict review, "Rescan", manual one-shot connections. Persistent
#   topology lives here.
#
# How to add a new device or folder:
#   1. Get the partner Device ID (Syncthing GUI → "This Device" or
#      `syncthing cli show system | jq -r .myID`).
#   2. Add an entry under `settings.devices.<name>.id` and reference
#      it from each folder it should share.
#   3. nixos-rebuild test → switch. The partner side has to accept
#      the share once (it appears as "New folder offered").
#
# Encryption: Syncthing's wire protocol is mutually-authenticated TLS
# between paired devices — no third party sees plaintext. At-rest
# encryption is your filesystem's job (LUKS for the laptop, app-level
# for Android, full-disk for the VPS provider).
#
# Ports on this host:
#   * 8384/TCP  — GUI, bound to 127.0.0.1, never exposed.
#   * 22000/TCP+UDP — sync. openDefaultPorts left FALSE because this
#     host is the initiator (laptop, no inbound). The VPS side opens
#     22000 in ufw — that's what makes the pairing work on a NAT
#     workstation.
#
# username injected by lib/mkHost.nix.
{
  username,
  lib,
  ...
}: let
  # Set after the VPS Syncthing daemon is up and the agent has
  # returned its Device ID and the chosen folder ID. Until then the
  # daemon runs without any declarative topology and the user can pair
  # ad-hoc through the GUI; once both values are filled, the Nix
  # expression takes over and the GUI becomes read-mostly.
  vpsDeviceId = "7TYSH4F-4G4BUUC-F5RVTAW-V4HHQNR-DKQR37A-BUBQBMG-TRKVKUT-2NIUFA7";
  brainFolderId = "brain-vault";
in {
  services.syncthing = lib.mkMerge [
    {
      enable = true;
      user = username;
      # Default data dir. The runtime DB and certificates live here;
      # actual shared folders are at their own paths.
      dataDir = "/home/${username}";
      configDir = "/home/${username}/.config/syncthing";

      # No public exposure — UI bound to localhost only.
      openDefaultPorts = false;
      guiAddress = "127.0.0.1:8384";
    }
    (lib.mkIf (vpsDeviceId != null && brainFolderId != null) {
      # Nix is authoritative for devices+folders. GUI edits are
      # silently reverted on the next service restart.
      overrideDevices = true;
      overrideFolders = true;

      settings = {
        devices.vps = {
          id = vpsDeviceId;
          name = "vps";
        };

        folders.${brainFolderId} = {
          label = "brain";
          path = "/home/${username}/Documents/obsidian/brain";
          devices = ["vps"];
          # Trashcan: deleted files kept for 30 days inside
          # .stversions/ on the recipient. Cheap safety net against
          # an "rm -rf inside a vault" accident on either side.
          versioning = {
            type = "trashcan";
            params.cleanoutDays = "30";
          };
        };
      };
    })
  ];
}
