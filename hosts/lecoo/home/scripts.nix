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
      battery-lecoo
      ;
  };

  home.packages = [
    lecoo-toggle
    lecoo-status
    battery-lecoo
  ];
}
