# sync.nix — Syncthing for cross-device file synchronisation.
#
# Use cases on this system:
#   - ~/Documents/secrets/vault.kdbx                ← Android (KeePassDX)
#   - ~/Documents/obsidian/brain                    ← VPS (Obsidian vault)
#   - ~/Documents/obsidian/hermes ↔ VPS ~/.hermes   ← VPS (hermes agent
#       config: config.yaml, skills/, plugins/, memories/, lore/, .env,
#       cron/output/. Asymmetric paths — Syncthing folder ID is the
#       binding, not the path.)
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
#      the share once (it appears as "New folder offered"); with
#      `autoAcceptFolders = true` on the partner, it latches without
#      manual action.
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
#     22000 — that's what makes the pairing work on a NAT
#     workstation.
#
# username injected by lib/mkHost.nix.
{username, ...}: let
  vpsDeviceId = "7TYSH4F-4G4BUUC-F5RVTAW-V4HHQNR-DKQR37A-BUBQBMG-TRKVKUT-2NIUFA7";
  phoneDeviceId = "CGUAONQ-5Z6GRBL-FQLWTSB-NTLOTJI-S6SW6PT-2XENWZ4-X7I3MP4-SRHAMAJ";

  # Trashcan defaults — cheap safety net against an "rm -rf" on
  # either side. 30 days is plenty for the Obsidian folders, which
  # already have a second history layer (Obsidian Git on brain, the
  # VPS side for hermes).
  trashcan30d = {
    type = "trashcan";
    params.cleanoutDays = "30";
  };

  # `simple` for the KeePass vault, and deliberately NOT `staggered`.
  #
  # Why versioning matters more here than anywhere else: vault.kdbx is a
  # single binary blob with two independent writers (KeePassXC on this
  # host, KeePassDX on the phone). Syncthing cannot merge it, so the
  # model is last-writer-wins. Each side keeps the database in memory
  # and only re-reads the file on open — so a client holding a stale
  # snapshot silently overwrites the other side's newer work. There is
  # no conflict file in that case: Syncthing sees an ordinary edit.
  # Versioning is the only layer that catches it, because it triggers
  # inside Syncthing at replacement time and does not care which
  # application misbehaved.
  #
  # Why not trashcan: it keeps exactly ONE displaced version per file,
  # so each new overwrite destroys the previous archive. Observed
  # 2026-09-30: two phone displacements 24 seconds apart
  # (14:14:18 / 14:14:42) — the desktop version archived at 14:14:18
  # was erased by the second one, unrecoverably (ext4, no snapshots).
  #
  # Why not staggered: its retention is interval-bucketed — for the
  # first hour it keeps "the oldest version in every 30-seconds
  # interval" (docs.syncthing.net/users/versioning.html). Two
  # overwrites inside one bucket collapse into a single survivor, so
  # burst protection depends on bucket alignment. A rapid burst of
  # phone saves is exactly the scenario we need to survive.
  #
  # `simple` keeps the last N versions per file with no thinning, which
  # is deterministic under bursts. Cost is negligible: the vault is
  # ~85 KB and displaced ~8 times per 40 days, so keep=25 is a few MB
  # and months of depth.
  simpleVersions = {
    type = "simple";
    params.keep = "25";
  };
in {
  services.syncthing = {
    enable = true;
    user = username;
    # Default data dir. The runtime DB and certificates live here;
    # actual shared folders are at their own paths.
    dataDir = "/home/${username}";
    configDir = "/home/${username}/.config/syncthing";

    # No public exposure — UI bound to localhost only.
    openDefaultPorts = false;
    guiAddress = "127.0.0.1:8384";

    # Nix is authoritative for devices+folders. GUI edits are
    # silently reverted on the next service restart.
    overrideDevices = true;
    overrideFolders = true;

    settings = {
      devices = {
        vps = {
          id = vpsDeviceId;
          name = "vps";
        };

        phone = {
          id = phoneDeviceId;
          name = "phone";
        };
      };

      folders = {
        # KeePass vault — shared with Android for KeePassDX.
        # Contains ~/Documents/secrets/vault.kdbx; keep the folder
        # narrow so only password-vault material is shared to mobile.
        #
        # Versioning: `simple` (see the simpleVersions binding above).
        # This folder has NO second history layer — unlike brain
        # (Obsidian Git) — so Syncthing's .stversions is the only
        # rollback path for the vault. Do not downgrade it to trashcan.
        "keepass-vault" = {
          label = "keepass";
          path = "/home/${username}/Documents/secrets";
          devices = ["phone"];
          versioning = simpleVersions;
        };

        # Obsidian vault — primary knowledge base, two-layer sync
        # (Syncthing for state, Obsidian Git for history).
        # See decisions/0012-obsidian-two-layer-sync.md.
        "brain-vault" = {
          label = "brain";
          path = "/home/${username}/Documents/obsidian/brain";
          devices = ["vps" "phone"];
          versioning = trashcan30d;
        };

        # hermes agent config — VPS-resident agent's mutable
        # configuration kept editable from the workstation.
        # Asymmetric path: VPS ~/.hermes/, workstation
        # ~/Documents/obsidian/hermes/. Folder ID
        # `hermes-config` is the canonical binding; the partner
        # side ignores node/, audio_cache/, media/, sessions/,
        # git/, *.sqlite*, *.db*, *.log, *.tmp, __pycache__/
        # via its own .stignore.
        "hermes-config" = {
          label = "hermes";
          path = "/home/${username}/Documents/obsidian/hermes";
          devices = ["vps"];
          versioning = trashcan30d;
        };
      };
    };
  };
}
