# ec.nix — Lecoo IT5571 EC daemon NixOS module.
#
# Exposes services.lecoo-ctrl.enable. The lecoo-ctrl package (own
# derivation in hosts/lecoo/pkgs/lecoo-ctrl/) controls fan curves and
# battery charge thresholds via /dev/port (raw x86 I/O) and a zbus
# D-Bus interface. Lives under hosts/lecoo/ because the EC chip is
# unique to this platform.
{
  config,
  pkgs,
  lib,
  ...
}: {
  options.services.lecoo-ctrl = with lib; {
    enable = mkEnableOption "Lecoo EC Control Daemon";

    package = mkOption {
      type = types.package;
      default = pkgs.lecoo-ctrl;
      defaultText = literalExpression "pkgs.lecoo-ctrl";
      description = "Lecoo Control Center package providing lecoo-ec-daemon and lecoo-ctrl.";
    };
  };

  config = lib.mkIf config.services.lecoo-ctrl.enable {
    # EC control daemon — reads/writes ITE IT5571-07 Super I/O chip via
    # /dev/port (raw x86 port I/O).  Uses zbus (D-Bus) for sleep/wake/
    # charger events and interprocess (Unix domain socket) for IPC with
    # lecoo-ctrl CLI.  Logs to journald via systemd-journal-logger.
    #
    # Power-profile coexistence with power-profiles-daemon
    # (modules/hardware/form-factor/laptop.nix):
    #   lecoo-ctrl power           → EC-level TDP / power limits (firmware)
    #   power-profiles-daemon      → OS-level platform_profile + EPP via amd_pmf
    # They do not conflict directly, but mismatched profiles (e.g.
    # lecoo silent + PPD performance) produce suboptimal results.
    # Coordinate profiles for synergy.
    #
    # Hardening: this daemon needs raw port I/O (CAP_SYS_RAWIO) and
    # access to /dev/port and /dev/mem to talk to the Super I/O chip.
    # Everything else is locked down via the systemd sandbox so a bug
    # in the daemon cannot reach the rest of the filesystem, escalate
    # privileges, or load kernel modules. Telemetry egress is left
    # open by intent — upstream uses the data to improve the daemon.
    systemd.services.lecoo-ec-daemon = {
      description = "Lecoo EC Control Daemon";
      after = ["network.target"];
      wantedBy = ["multi-user.target"];

      serviceConfig = {
        Type = "simple";
        ExecStart = "${config.services.lecoo-ctrl.package}/bin/lecoo-ec-daemon";
        Restart = "on-failure";
        RestartSec = 5;
        User = "root";
        StateDirectory = "lecoo-control";

        # ── Capability scope ──────────────────────────────────────────
        # Raw x86 port I/O is the only privileged operation the daemon
        # performs. Drop everything else.
        CapabilityBoundingSet = ["CAP_SYS_RAWIO"];
        AmbientCapabilities = ["CAP_SYS_RAWIO"];
        NoNewPrivileges = true;

        # ── Filesystem ────────────────────────────────────────────────
        # /dev/port and /dev/mem are required for raw I/O; nothing else
        # under /dev is needed (no GPU, no input, no audio).
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = false;
        DeviceAllow = [
          "/dev/port rw"
          "/dev/mem rw"
        ];
        ReadWritePaths = ["/var/lib/lecoo-control"];

        # ── Kernel surface ────────────────────────────────────────────
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectControlGroups = true;
        ProtectClock = true;
        ProtectHostname = true;
        ProtectProc = "invisible";
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        RestrictNamespaces = true;
        SystemCallArchitectures = "native";
        SystemCallFilter = [
          "@system-service"
          "~@privileged"
          "~@resources"
        ];

        # Telemetry egress is intentionally NOT blocked. Upstream
        # (LaVashikk/Lecoo-Control-Center) uses anonymised crash and
        # usage data to drive the daemon forward. The user has opted in.
      };
    };

    # CLI in system PATH — usable by both root (systemctl) and user.
    environment.systemPackages = [config.services.lecoo-ctrl.package];
  };
}
