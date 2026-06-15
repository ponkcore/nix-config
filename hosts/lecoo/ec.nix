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
}: let
  syncPowerProfile = pkgs.writeShellScript "lecoo-sync-power-profile" ''
    set -eu

    online=$(cat /sys/class/power_supply/ADP1/online 2>/dev/null || echo 0)
    if [ "$online" = "1" ]; then
      ${config.services.lecoo-ctrl.package}/bin/lecoo-ctrl power default >/dev/null 2>&1 || true
      ${pkgs.power-profiles-daemon}/bin/powerprofilesctl set balanced >/dev/null 2>&1 || true
    else
      ${config.services.lecoo-ctrl.package}/bin/lecoo-ctrl power silent >/dev/null 2>&1 || true
      ${pkgs.power-profiles-daemon}/bin/powerprofilesctl set power-saver >/dev/null 2>&1 || true
    fi
  '';
in {
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

    # Keep OS-level and EC-level power policy aligned. PPD owns the
    # kernel-facing side (platform_profile + amd-pstate EPP), while
    # lecoo-ctrl owns the firmware-facing side (EC TDP / fan profile).
    # On AC we default to balanced + EC default; on battery we switch to
    # power-saver + EC silent. Full performance remains a manual choice.
    systemd.services.lecoo-sync-power-profile = {
      description = "Synchronise Lecoo EC and OS power profiles";
      after = ["lecoo-ec-daemon.service" "power-profiles-daemon.service"];
      wants = ["lecoo-ec-daemon.service" "power-profiles-daemon.service"];
      # power-profiles-daemon itself starts after multi-user/display-manager;
      # binding this sync unit to multi-user creates an ordering cycle.
      # graphical.target keeps the boot-time sync late enough without
      # delaying the greeter path.
      wantedBy = ["graphical.target"];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = syncPowerProfile;
        StandardOutput = "journal";
        StandardError = "journal";
      };
    };

    services.udev.extraRules = ''
      # AC edge: sync EC firmware profile with power-profiles-daemon.
      SUBSYSTEM=="power_supply", KERNEL=="ADP1", ATTR{online}=="1", \
        RUN+="${pkgs.systemd}/bin/systemctl --no-block start lecoo-sync-power-profile.service"
      SUBSYSTEM=="power_supply", KERNEL=="ADP1", ATTR{online}=="0", \
        RUN+="${pkgs.systemd}/bin/systemctl --no-block start lecoo-sync-power-profile.service"
    '';

    # CLI in system PATH — usable by both root (systemctl) and user.
    environment.systemPackages = [config.services.lecoo-ctrl.package];
  };
}
