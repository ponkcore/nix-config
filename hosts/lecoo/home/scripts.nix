# hosts/lecoo/home/scripts.nix — Lecoo-only HM helper scripts.
#
# Four EC-driven scripts:
#   - lecoo-charge-current : prints the current FlexiCharger mode as a
#     bare keyword (full/high/balanced/lifespan/desk/unknown). Internal
#     helper consumed by the other three; not in home.packages.
#   - lecoo-toggle         : right-click handler that cycles to the next
#     FlexiCharger mode and re-emits battery-lecoo JSON for waybar.
#   - lecoo-status         : standalone waybar exec that renders the
#     current charge-mode as JSON (icon + tooltip).
#   - battery-lecoo        : the merged system-battery + EC-charge-mode
#     widget exec. This is what custom/battery actually runs every
#     interval and right after every toggle.
# All call `lecoo-ctrl` which is platform-specific (ITE IT5571-07 on
# Emdoor N155A) and meaningless on any other host.
#
# Exposed via _module.args so the host-scoped waybar fragment can embed
# the /nix/store paths without re-deriving them.
{pkgs, ...}: let
  # ── Helper: detect current FlexiCharger mode from `lecoo-ctrl charge`
  # Output is one of: full / high / balanced / lifespan / desk / unknown.
  # Used by both lecoo-toggle (to decide the next mode) and lecoo-status
  # (to render the waybar JSON). Pure stdout, no side effects.
  # Mapping note (verified empirically 2026-05-31): the lecoo-ctrl 0.4.0
  # CLI help advertises desk = 40 %, but the EC actually reports
  # `Stop charging at: 50%` for that mode. The 40-50 hysteresis means
  # the cap is 50; CLI help text is misleading. Trust the runtime read,
  # not the help string.
  charge-current = pkgs.writeShellScriptBin "lecoo-charge-current" ''
    output=$(${pkgs.lecoo-ctrl}/bin/lecoo-ctrl charge 2>/dev/null)
    if echo "$output" | ${pkgs.gnugrep}/bin/grep -q "Full Capacity"; then
      echo full
      exit 0
    fi
    stop=$(echo "$output" | ${pkgs.gnugrep}/bin/grep -oP 'Stop charging at:\s*\K\d+' 2>/dev/null)
    case "$stop" in
      95) echo high ;;
      80) echo balanced ;;
      60) echo lifespan ;;
      50) echo desk ;;
      *)  echo unknown ;;
    esac
  '';

  # ── Charge mode toggle ─────────────────────────────────────────────
  # Cycles through all five FlexiCharger modes (Lecoo Control Center
  # equivalents):
  #   full      — 100 %  (no limit)
  #   high      — 95 %
  #   balanced  — 80 %   (70-80 hysteresis)
  #   lifespan  — 60 %   (55-60 hysteresis)
  #   desk      — 40 %   (40-50 hysteresis, plugged-in scenario)
  # Order chosen for descending battery ceiling so a sequence of right
  # clicks moves the user toward more conservative limits — the common
  # direction. Wraps from desk back to full.
  #
  # After the mode flip we immediately re-emit the merged battery JSON
  # (battery-lecoo) so waybar repaints without waiting for the next
  # 5 s tick.
  lecoo-toggle = pkgs.writeShellScriptBin "lecoo-toggle" ''
    current=$(${charge-current}/bin/lecoo-charge-current)
    case "$current" in
      full)     next=high ;;
      high)     next=balanced ;;
      balanced) next=lifespan ;;
      lifespan) next=desk ;;
      desk)     next=full ;;
      *)        next=balanced ;;
    esac
    ${pkgs.lecoo-ctrl}/bin/lecoo-ctrl charge "$next" >/dev/null 2>&1
    exec ${battery-lecoo}/bin/battery-lecoo
  '';

  lecoo-status = pkgs.writeShellScriptBin "lecoo-status" ''
    case "$(${charge-current}/bin/lecoo-charge-current)" in
      full)     printf '{"text":"","class":"full","tooltip":"Charge: Full (100%%)"}\n' ;;
      high)     printf '{"text":"95","class":"high","tooltip":"Charge: High (90-95%%)"}\n' ;;
      balanced) printf '{"text":"","class":"balanced","tooltip":"Charge: Balanced (70-80%%)"}\n' ;;
      lifespan) printf '{"text":"60","class":"lifespan","tooltip":"Charge: Lifespan (55-60%%)"}\n' ;;
      desk)     printf '{"text":"40","class":"desk","tooltip":"Charge: Desk (40-50%%)"}\n' ;;
      *)        printf '{"text":"?","class":"balanced","tooltip":"Charge: Unknown"}\n' ;;
    esac
  '';

  # ── Ultra economy toggle ───────────────────────────────────────────
  # Manual, explicit battery-saving profile. This intentionally does
  # NOT run on AC plug/unplug: fixed 120↔60 Hz switches are DRM modesets
  # and blank the eDP panel for ~1 s. As a user-clicked mode that blink is
  # expected; as an automatic power-edge side effect it is not.
  #
  # Eco mode levers (cumulative ~8-10 W saving from baseline):
  #   - 60 Hz panel (DRM modeset, ~1s blank)          −1.5-2 W
  #   - Hyprland animations off                        −0.2-0.3 W
  #   - Hyprland blur/shadow off                       −0.1-0.2 W
  #   - SMT disable (16 threads → 8 cores)             −0.5-1.5 W
  #   - CPU boost off + 2 GHz max freq cap             −0.5-1.5 W
  #   - EPP=power (0xFF, remove balance_power override) −0.3-0.8 W
  #   - PPD power-saver + EC silent + GPU DPM low      (already on battery)
  #   - Stop Docker + libvirtd                         −0.2-1 W
  #
  # Does not touch display brightness, Bluetooth, Wi-Fi, or user
  # applications. BT and WiFi are managed manually by the user.
  ultra-economy-toggle = pkgs.writeShellScriptBin "ultra-economy-toggle" ''
    set -eu

    # Session-local saved state lives in tmpfs (wiped on reboot).
    # Persistent eco state file lives in /var/lib (survives reboots)
    # — checked by cpu-boost-restore.service and AC-plug udev handlers.
    runtime="''${XDG_RUNTIME_DIR:-/tmp}/ultra-economy"
    state="$runtime/state"
    persistent_state="/var/lib/lecoo-eco/state-on"
    saved_animations="$runtime/animations"
    saved_smt="$runtime/smt"
    saved_boost="$runtime/boost"
    saved_maxfreq="$runtime/maxfreq"

    mkdir -p "$runtime"

    notify_waybar() {
      ${pkgs.procps}/bin/pkill -RTMIN+8 -f '/bin/waybar' >/dev/null 2>&1 || true
    }

    set_gpu_level() {
      level=$1
      case "$level" in
        low|auto) ;;
        *) return 0 ;;
      esac
      printf '%s\n' "$level" | sudo -n ${pkgs.coreutils}/bin/tee /sys/class/drm/card1/device/power_dpm_force_performance_level >/dev/null 2>&1 || true
    }

    apply_power_baseline() {
      online=$(cat /sys/class/power_supply/ADP1/online 2>/dev/null || echo 0)
      if [ "$online" = "1" ]; then
        ${pkgs.power-profiles-daemon}/bin/powerprofilesctl set balanced >/dev/null 2>&1 || true
        ${pkgs.lecoo-ctrl}/bin/lecoo-ctrl power default >/dev/null 2>&1 || true
        set_gpu_level auto
      else
        ${pkgs.power-profiles-daemon}/bin/powerprofilesctl set power-saver >/dev/null 2>&1 || true
        ${pkgs.lecoo-ctrl}/bin/lecoo-ctrl power silent >/dev/null 2>&1 || true
        set_gpu_level low
      fi
    }

    # Restore CPU settings saved during eco entry.
    restore_cpu() {
      if [ -r "$saved_smt" ]; then
        sudo -n ${pkgs.coreutils}/bin/tee /sys/devices/system/cpu/smt/control < "$saved_smt" >/dev/null 2>&1 || true
        rm -f "$saved_smt"
      fi
      if [ -r "$saved_boost" ]; then
        for p in /sys/devices/system/cpu/cpufreq/policy*/boost; do
          sudo -n ${pkgs.coreutils}/bin/tee "$p" < "$saved_boost" >/dev/null 2>&1 || true
        done
        rm -f "$saved_boost"
      fi
      if [ -r "$saved_maxfreq" ]; then
        for p in /sys/devices/system/cpu/cpufreq/policy*/amd_pstate_max_freq; do
          sudo -n ${pkgs.coreutils}/bin/tee "$p" < "$saved_maxfreq" >/dev/null 2>&1 || true
        done
        rm -f "$saved_maxfreq"
      fi
    }

    if [ "$(cat "$state" 2>/dev/null || true)" = "on" ]; then
      # ── Leave ultra economy ──────────────────────────────────
      ${pkgs.hyprland}/bin/hyprctl keyword monitor "eDP-1, 2880x1800@120, 0x0, 1.8" >/dev/null 2>&1 || true

      if [ -r "$saved_animations" ]; then
        animations=$(cat "$saved_animations")
        case "$animations" in
          0|1) ${pkgs.hyprland}/bin/hyprctl keyword animations:enabled "$animations" >/dev/null 2>&1 || true ;;
        esac
        rm -f "$saved_animations"
      else
        ${pkgs.hyprland}/bin/hyprctl keyword animations:enabled 1 >/dev/null 2>&1 || true
      fi

      # Restore Hyprland visual effects.
      ${pkgs.hyprland}/bin/hyprctl keyword decoration:blur:enabled 1 >/dev/null 2>&1 || true
      ${pkgs.hyprland}/bin/hyprctl keyword decoration:shadow:enabled 1 >/dev/null 2>&1 || true

      # Restore CPU settings.
      restore_cpu

      # Restart stopped services.
      sudo -n ${pkgs.systemd}/bin/systemctl start docker.service libvirtd.service 2>/dev/null || true

      # Restore power baseline (re-enables battery-epp-override on battery).
      apply_power_baseline
      # Re-apply EPP override since PPD may have reset it.
      online=$(cat /sys/class/power_supply/ADP1/online 2>/dev/null || echo 0)
      if [ "$online" = "0" ]; then
        sudo -n ${pkgs.systemd}/bin/systemctl start battery-epp-override.service 2>/dev/null || true
      fi

      echo off > "$state"
      sudo -n ${pkgs.coreutils}/bin/rm -f "$persistent_state" 2>/dev/null || true
      notify_waybar
      exit 0
    fi

    # ── Enter ultra economy ───────────────────────────────────
    # Save session-local state so leaving the mode restores what the
    # user had before the click.
    ${pkgs.hyprland}/bin/hyprctl getoption animations:enabled 2>/dev/null \
      | ${pkgs.gnugrep}/bin/grep -oP '^int:\s*\K[01]' > "$saved_animations" 2>/dev/null || true

    # Save CPU state.
    cat /sys/devices/system/cpu/smt/control > "$saved_smt" 2>/dev/null || true
    cat /sys/devices/system/cpu/cpufreq/policy0/boost > "$saved_boost" 2>/dev/null || true
    cat /sys/devices/system/cpu/cpufreq/policy0/amd_pstate_max_freq > "$saved_maxfreq" 2>/dev/null || true

    # Panel: 120 → 60 Hz (DRM modeset, ~1s blank).
    ${pkgs.hyprland}/bin/hyprctl keyword monitor "eDP-1, 2880x1800@60, 0x0, 1.8" >/dev/null 2>&1 || true

    # Hyprland: disable animations + visual effects.
    ${pkgs.hyprland}/bin/hyprctl keyword animations:enabled 0 >/dev/null 2>&1 || true
    ${pkgs.hyprland}/bin/hyprctl keyword decoration:blur:enabled 0 >/dev/null 2>&1 || true
    ${pkgs.hyprland}/bin/hyprctl keyword decoration:shadow:enabled 0 >/dev/null 2>&1 || true

    # CPU: disable SMT (16 threads → 8 cores), disable boost, cap at 2 GHz.
    sudo -n ${pkgs.coreutils}/bin/tee /sys/devices/system/cpu/smt/control <<< "off" >/dev/null 2>&1 || true
    for p in /sys/devices/system/cpu/cpufreq/policy*/boost; do
      echo 0 | sudo -n ${pkgs.coreutils}/bin/tee "$p" >/dev/null 2>&1 || true
    done
    for p in /sys/devices/system/cpu/cpufreq/policy*/amd_pstate_max_freq; do
      echo 2000000 | sudo -n ${pkgs.coreutils}/bin/tee "$p" >/dev/null 2>&1 || true
    done

    # Power: PPD power-saver + EC silent + GPU DPM low.
    ${pkgs.power-profiles-daemon}/bin/powerprofilesctl set power-saver >/dev/null 2>&1 || true
    ${pkgs.lecoo-ctrl}/bin/lecoo-ctrl power silent >/dev/null 2>&1 || true
    set_gpu_level low

    # EPP: explicitly set power (0xFF) for maximum efficiency in eco
    # mode. PPD power-saver sets this, but battery-epp-override may
    # have already overwritten it. Stop the override service first,
    # then set EPP=power directly on all CPUs.
    sudo -n ${pkgs.systemd}/bin/systemctl stop battery-epp-override.service 2>/dev/null || true
    for cpu in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
      echo power | sudo -n ${pkgs.coreutils}/bin/tee "$cpu" >/dev/null 2>&1 || true
    done

    # Stop heavyweight services — but only if no containers/VMs
    # are running. Stopping Docker mid-container can cause data
    # loss on unclean shutdowns.
    # Source: audit 2026-06-28-full-session-audit §N
    if sudo -n ${pkgs.systemd}/bin/systemctl is-active docker.service >/dev/null 2>&1; then
      running=$(${pkgs.docker}/bin/docker ps -q 2>/dev/null || true)
      if [ -n "$running" ]; then
        ${pkgs.libnotify}/bin/notify-send "Eco mode" "Containers running — stop them first" 2>/dev/null || true
      else
        sudo -n ${pkgs.systemd}/bin/systemctl stop docker.service 2>/dev/null || true
      fi
    fi
    sudo -n ${pkgs.systemd}/bin/systemctl stop libvirtd.service 2>/dev/null || true

    echo on > "$state"
    # Write persistent state file — survives reboots, checked by
    # cpu-boost-restore.service (skip boost=1 if eco active) and
    # AC-plug udev handlers (skip power profile reset if eco active).
    echo on | sudo -n ${pkgs.coreutils}/bin/tee "$persistent_state" >/dev/null 2>&1 || true
    notify_waybar
  '';

  ultra-economy-status = pkgs.writeShellScriptBin "ultra-economy-status" ''
    runtime="''${XDG_RUNTIME_DIR:-/tmp}/ultra-economy"
    state="$runtime/state"
    persistent_state="/var/lib/lecoo-eco/state-on"

    # Check both session state and persistent state — persistent
    # survives reboots, session is cleared on logout.
    if [ "$(cat "$state" 2>/dev/null || true)" = "on" ] || [ -f "$persistent_state" ]; then
      printf '{"text":"󰗌","class":"on"}\n'
    else
      printf '{"text":"󰗌","class":"off"}\n'
    fi
  '';

  # ── Merged battery + lecoo status (waybar custom/battery exec) ─────
  battery-lecoo = pkgs.writeShellScriptBin "battery-lecoo" ''
    CAP=$(cat /sys/class/power_supply/BAT0/capacity 2>/dev/null || echo "0")
    STATUS=$(cat /sys/class/power_supply/BAT0/status 2>/dev/null || echo "Unknown")

    LECOO_OUTPUT=$(${pkgs.lecoo-ctrl}/bin/lecoo-ctrl charge 2>/dev/null)
    if echo "$LECOO_OUTPUT" | ${pkgs.gnugrep}/bin/grep -q "Full Capacity"; then
      LECOO_LIMIT="100"
    else
      LECOO_LIMIT=$(echo "$LECOO_OUTPUT" | ${pkgs.gnugrep}/bin/grep -oP 'Stop charging at:\s*\K\d+' 2>/dev/null)
      [ -z "$LECOO_LIMIT" ] && LECOO_LIMIT="?"
    fi

    case "$STATUS" in
      Charging)    ALT="charging" ;;
      Full)        ALT="full" ;;
      *)           ALT="discharging" ;;
    esac

    # Empty class string by default; flips to "low" when discharging
    # below 20 % so the CSS `#custom-battery.low { color: red }`
    # rule kicks in (waybar renders custom-module class strings as
    # element classes via the `class` JSON field).
    CLASS=""
    if [ "$STATUS" = "Discharging" ] && [ "$CAP" -lt 20 ]; then
      CLASS="low"
    fi

    # Tooltip uses Nerd Font glyphs:
    #   󱊣  nf-md-battery_high (U+F12A3) — current charge level
    #   󱞜  nf-md-battery_lock (U+F179C) — EC-enforced charge ceiling
    TOOLTIP="$CAP% 󱊣 | $LECOO_LIMIT% 󱞜"
    printf '{"text":"%s","alt":"%s","class":"%s","percentage":%s,"tooltip":"%s"}\n' \
      "$CAP" "$ALT" "$CLASS" "$CAP" "$TOOLTIP"
  '';
in {
  _module.args = {
    inherit
      lecoo-toggle
      lecoo-status
      ultra-economy-toggle
      ultra-economy-status
      battery-lecoo
      ;
  };

  home.packages = [
    lecoo-toggle
    lecoo-status
    ultra-economy-toggle
    ultra-economy-status
    battery-lecoo
  ];
}
