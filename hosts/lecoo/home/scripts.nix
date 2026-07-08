# hosts/lecoo/home/scripts.nix — Lecoo-only HM helper scripts.
#
# Lecoo-specific EC helpers.
#
# Kept as standalone scripts because quickshell and future shell/UI
# components may need the same power/charge information without being
# tied to a specific bar implementation.
{
  pkgs,
  hostDisplay,
  ...
}: let
  display = hostDisplay;
  # ── Helper: detect current FlexiCharger mode from `lecoo-ctrl charge`
  # Output is one of: full / high / balanced / lifespan / desk / unknown.
  # Used by both lecoo-toggle (to decide the next mode) and lecoo-status.
  # Pure stdout, no side effects.
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
  # After the mode flip we return the refreshed merged battery JSON so
  # any caller can update immediately without waiting for a polling tick.
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

  # ── Composite power modes ──────────────────────────────────────────
  # User-facing modes on this host are composed from:
  #   - powerprofilesctl (performance / balanced / power-saver)
  #   - lecoo-ctrl power (default / silent)
  #   - GPU DPM (auto / low)
  #   - extra aggressive eco+ levers (60 Hz, SMT off, etc.)
  #
  # State files:
  #   /var/lib/lecoo-power-mode/current   -> performance|balanced|eco|eco+
  #   /var/lib/lecoo-eco/state-on         -> legacy eco+ marker (compat)
  #
  # AC-edge transition table:
  #   unplug: balanced->eco, eco->eco, performance->eco, eco+->eco+
  #   plug:   balanced->balanced, eco->balanced, performance->performance, eco+->balanced
  lecoo-power-mode = pkgs.writeShellScriptBin "lecoo-power-mode" ''
    set -eu

    runtime="''${XDG_RUNTIME_DIR:-/tmp}/ultra-economy"
    ultra_state="$runtime/state"
    legacy_persistent_state="/var/lib/lecoo-eco/state-on"
    mode_dir="/var/lib/lecoo-power-mode"
    mode_file="$mode_dir/current"
    saved_animations="$runtime/animations"
    saved_smt="$runtime/smt"
    saved_boost="$runtime/boost"
    saved_maxfreq="$runtime/maxfreq"

    mkdir -p "$runtime"

    get_mode() {
      if [ -r "$mode_file" ]; then
        cat "$mode_file"
      elif [ -f "$legacy_persistent_state" ] || [ "$(cat "$ultra_state" 2>/dev/null || true)" = "on" ]; then
        printf 'eco+\n'
      else
        online=$(cat /sys/class/power_supply/ADP1/online 2>/dev/null || echo 0)
        if [ "$online" = "1" ]; then printf 'balanced\n'; else printf 'eco\n'; fi
      fi
    }

    set_mode_state() {
      mode=$1
      sudo -n ${pkgs.coreutils}/bin/mkdir -p "$mode_dir" >/dev/null 2>&1 || true
      printf '%s\n' "$mode" | sudo -n ${pkgs.coreutils}/bin/tee "$mode_file" >/dev/null 2>&1 || true
    }

    set_gpu_level() {
      level=$1
      case "$level" in low|auto) ;; *) return 0 ;; esac
      printf '%s\n' "$level" | sudo -n ${pkgs.coreutils}/bin/tee /sys/class/drm/card1/device/power_dpm_force_performance_level >/dev/null 2>&1 || true
    }

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

    leave_eco_plus() {
      ${pkgs.hyprland}/bin/hyprctl keyword monitor "${display.internalMonitor}, ${display.internalMode}, 0x0, ${display.internalScale}" >/dev/null 2>&1 || true
      if [ -r "$saved_animations" ]; then
        animations=$(cat "$saved_animations")
        case "$animations" in 0|1) ${pkgs.hyprland}/bin/hyprctl keyword animations:enabled "$animations" >/dev/null 2>&1 || true ;; esac
        rm -f "$saved_animations"
      else
        ${pkgs.hyprland}/bin/hyprctl keyword animations:enabled 1 >/dev/null 2>&1 || true
      fi
      ${pkgs.hyprland}/bin/hyprctl keyword decoration:blur:enabled 1 >/dev/null 2>&1 || true
      ${pkgs.hyprland}/bin/hyprctl keyword decoration:shadow:enabled 1 >/dev/null 2>&1 || true
      restore_cpu
      sudo -n ${pkgs.systemd}/bin/systemctl start docker.service libvirtd.service 2>/dev/null || true
      echo off > "$ultra_state"
      sudo -n ${pkgs.coreutils}/bin/rm -f "$legacy_persistent_state" >/dev/null 2>&1 || true
    }

    enter_eco_plus() {
      ${pkgs.hyprland}/bin/hyprctl getoption animations:enabled 2>/dev/null | ${pkgs.gnugrep}/bin/grep -oP '^int:\s*\K[01]' > "$saved_animations" 2>/dev/null || true
      cat /sys/devices/system/cpu/smt/control > "$saved_smt" 2>/dev/null || true
      cat /sys/devices/system/cpu/cpufreq/policy0/boost > "$saved_boost" 2>/dev/null || true
      cat /sys/devices/system/cpu/cpufreq/policy0/amd_pstate_max_freq > "$saved_maxfreq" 2>/dev/null || true
      ${pkgs.hyprland}/bin/hyprctl keyword monitor "${display.internalMonitor}, ${display.internalModeEco}, 0x0, ${display.internalScale}" >/dev/null 2>&1 || true
      ${pkgs.hyprland}/bin/hyprctl keyword animations:enabled 0 >/dev/null 2>&1 || true
      ${pkgs.hyprland}/bin/hyprctl keyword decoration:blur:enabled 0 >/dev/null 2>&1 || true
      ${pkgs.hyprland}/bin/hyprctl keyword decoration:shadow:enabled 0 >/dev/null 2>&1 || true
      sudo -n ${pkgs.coreutils}/bin/tee /sys/devices/system/cpu/smt/control <<< "off" >/dev/null 2>&1 || true
      for p in /sys/devices/system/cpu/cpufreq/policy*/boost; do echo 0 | sudo -n ${pkgs.coreutils}/bin/tee "$p" >/dev/null 2>&1 || true; done
      for p in /sys/devices/system/cpu/cpufreq/policy*/amd_pstate_max_freq; do echo 2000000 | sudo -n ${pkgs.coreutils}/bin/tee "$p" >/dev/null 2>&1 || true; done
      ${pkgs.power-profiles-daemon}/bin/powerprofilesctl set power-saver >/dev/null 2>&1 || true
      ${pkgs.lecoo-ctrl}/bin/lecoo-ctrl power silent >/dev/null 2>&1 || true
      set_gpu_level low
      sudo -n ${pkgs.systemd}/bin/systemctl stop battery-epp-override.service 2>/dev/null || true
      for cpu in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do echo power | sudo -n ${pkgs.coreutils}/bin/tee "$cpu" >/dev/null 2>&1 || true; done
      if sudo -n ${pkgs.systemd}/bin/systemctl is-active docker.service >/dev/null 2>&1; then
        running=$(${pkgs.docker}/bin/docker ps -q 2>/dev/null || true)
        if [ -z "$running" ]; then sudo -n ${pkgs.systemd}/bin/systemctl stop docker.service >/dev/null 2>&1 || true; fi
      fi
      if sudo -n ${pkgs.systemd}/bin/systemctl is-active libvirtd.service >/dev/null 2>&1; then
        running_vms=$(sudo -n ${pkgs.libvirt}/bin/virsh list --state-running --name 2>/dev/null || true)
        if [ -z "$running_vms" ]; then sudo -n ${pkgs.systemd}/bin/systemctl stop libvirtd.service >/dev/null 2>&1 || true; fi
      fi
      echo on > "$ultra_state"
      echo on | sudo -n ${pkgs.coreutils}/bin/tee "$legacy_persistent_state" >/dev/null 2>&1 || true
    }

    apply_mode() {
      mode=$1
      case "$mode" in
        performance)
          leave_eco_plus
          ${pkgs.power-profiles-daemon}/bin/powerprofilesctl set performance >/dev/null 2>&1 || true
          ${pkgs.lecoo-ctrl}/bin/lecoo-ctrl power default >/dev/null 2>&1 || true
          set_gpu_level auto
          ;;
        balanced)
          leave_eco_plus
          ${pkgs.power-profiles-daemon}/bin/powerprofilesctl set balanced >/dev/null 2>&1 || true
          ${pkgs.lecoo-ctrl}/bin/lecoo-ctrl power default >/dev/null 2>&1 || true
          set_gpu_level auto
          ;;
        eco)
          leave_eco_plus
          ${pkgs.power-profiles-daemon}/bin/powerprofilesctl set power-saver >/dev/null 2>&1 || true
          ${pkgs.lecoo-ctrl}/bin/lecoo-ctrl power silent >/dev/null 2>&1 || true
          set_gpu_level low
          ;;
        eco+)
          enter_eco_plus
          ;;
        *)
          printf 'Unknown mode: %s\n' "$mode" >&2
          exit 1
          ;;
      esac
      set_mode_state "$mode"
    }

    transition_edge() {
      edge=$1
      current=$(get_mode)
      case "$edge:$current" in
        unplug:balanced) next=eco ;;
        unplug:eco) next=eco ;;
        unplug:performance) next=eco ;;
        unplug:eco+) next=eco+ ;;
        plug:balanced) next=balanced ;;
        plug:eco) next=balanced ;;
        plug:performance) next=performance ;;
        plug:eco+) next=balanced ;;
        *) next="$current" ;;
      esac
      apply_mode "$next"
    }

    case "''${1:-}" in
      get) get_mode ;;
      set) apply_mode "$2" ;;
      edge) transition_edge "$2" ;;
      *) printf 'Usage: lecoo-power-mode {get|set <mode>|edge <plug|unplug>}\n' >&2; exit 1 ;;
    esac
  '';

  lecoo-power-mode-status = pkgs.writeShellScriptBin "lecoo-power-mode-status" ''
    mode=$(${lecoo-power-mode}/bin/lecoo-power-mode get)
    case "$mode" in
      performance) printf '{"text":"P","class":"performance","tooltip":"Power mode: Performance"}\n' ;;
      balanced)    printf '{"text":"B","class":"balanced","tooltip":"Power mode: Balanced"}\n' ;;
      eco)         printf '{"text":"E","class":"eco","tooltip":"Power mode: Eco"}\n' ;;
      eco+)        printf '{"text":"E+","class":"eco-plus","tooltip":"Power mode: Eco+"}\n' ;;
      *)           printf '{"text":"?","class":"balanced","tooltip":"Power mode: Unknown"}\n' ;;
    esac
  '';

  # Backward-compat wrapper for existing callers.
  ultra-economy-toggle = pkgs.writeShellScriptBin "ultra-economy-toggle" ''
    exec ${lecoo-power-mode}/bin/lecoo-power-mode set eco+
  '';

  ultra-economy-status = pkgs.writeShellScriptBin "ultra-economy-status" ''
    exec ${lecoo-power-mode-status}/bin/lecoo-power-mode-status
  '';

  # ── Real-time power draw helper ────────────────────────────────────
  # On battery: BAT0/power_now gives total system draw (SoC + NVMe +
  #   WiFi + display + peripherals) — accurate.
  # On AC: amdgpu hwmon power1_input (PPT) gives SoC package power —
  #   doesn't include NVMe/WiFi/display, but best available without
  #   root. RAPL energy_uj is root-only.
  # Format: always "XX.XW" (zero-padded, 1 decimal) for stable width.
  power-draw = pkgs.writeShellScriptBin "power-draw" ''
    AC=$(cat /sys/class/power_supply/ADP1/online 2>/dev/null || echo 0)
    ECO=""
    if [ -f /var/lib/lecoo-eco/state-on ]; then
      ECO="1"
    fi
    if [ "$AC" = "1" ]; then
      PW=$(cat /sys/class/hwmon/hwmon1/power1_input 2>/dev/null || echo 0)
    else
      PW=$(cat /sys/class/power_supply/BAT0/power_now 2>/dev/null || echo 0)
    fi
    WATTS=$(${pkgs.gawk}/bin/awk -v u="$PW" 'BEGIN{printf "%04.1f", u/1000000}')
    if [ -n "$ECO" ]; then
      CLASS="eco"
    elif [ "$AC" = "1" ]; then
      CLASS="ac"
    else
      CLASS="battery"
    fi
    printf '{"text":"%sW","class":"%s"}\n' "$WATTS" "$CLASS"
  '';

  # ── Merged battery + lecoo status helper ───────────────────────────
  battery-lecoo = pkgs.writeShellScriptBin "battery-lecoo" ''
    CAP=$(cat /sys/class/power_supply/BAT0/capacity 2>/dev/null || echo "0")
    [ "$CAP" -gt 99 ] && CAP=99
    STATUS=$(cat /sys/class/power_supply/BAT0/status 2>/dev/null || echo "Unknown")

    LECOO_OUTPUT=$(${pkgs.lecoo-ctrl}/bin/lecoo-ctrl charge 2>/dev/null)
    if echo "$LECOO_OUTPUT" | ${pkgs.gnugrep}/bin/grep -q "Full Capacity"; then
      LECOO_LIMIT="99"
    else
      LECOO_LIMIT=$(echo "$LECOO_OUTPUT" | ${pkgs.gnugrep}/bin/grep -oP 'Stop charging at:\s*\K\d+' 2>/dev/null)
      [ -z "$LECOO_LIMIT" ] && LECOO_LIMIT="0"
    fi
    [ "$LECOO_LIMIT" -gt 99 ] && LECOO_LIMIT=99

    case "$STATUS" in
      Charging)    ALT="charging" ;;
      Full)        ALT="full" ;;
      *)           ALT="discharging" ;;
    esac

    # Empty class string by default; flips to "low" when discharging
    # below 20 % so the CSS `#custom-battery.low { color: red }`
    # rule kicks in when the caller maps the returned class to UI state
    # element classes via the `class` JSON field).
    CLASS=""
    if [ "$STATUS" = "Discharging" ] && [ "$CAP" -lt 20 ]; then
      CLASS="low"
    fi

    # Tooltip uses Nerd Font glyphs:
    #   󱊣  nf-md-battery_high (U+F12A3) — current charge level
    #   󱞜  nf-md-battery_lock (U+F179C) — EC-enforced charge ceiling
    TOOLTIP=$(printf '%02d%% | %02d%%' "$CAP" "$LECOO_LIMIT")
    TEXT="$(printf '%02d' "$CAP")% | $(printf '%02d' "$LECOO_LIMIT")%"
    printf '{"text":"%s","alt":"%s","class":"%s","percentage":%s,"tooltip":"%s"}\n' \
      "$TEXT" "$ALT" "$CLASS" "$CAP" "$TOOLTIP"
  '';
in {
  _module.args = {
    inherit
      lecoo-toggle
      lecoo-status
      lecoo-power-mode
      lecoo-power-mode-status
      ultra-economy-toggle
      ultra-economy-status
      battery-lecoo
      power-draw
      ;
  };

  home.packages = [
    lecoo-toggle
    lecoo-status
    lecoo-power-mode
    lecoo-power-mode-status
    ultra-economy-toggle
    ultra-economy-status
    battery-lecoo
    power-draw
  ];
}
