# hosts/lecoo/home/scripts.nix — Lecoo-only HM helper scripts.
#
# The three EC-driven scripts: charge-mode toggle, charge-mode status
# probe (waybar exec), and the merged battery+lecoo waybar widget.
# All three call `lecoo-ctrl` which is platform-specific (ITE IT5571-07
# on Emdoor N155A) and meaningless on any other host.
#
# Exposed via _module.args so the host-scoped waybar fragment can embed
# the /nix/store paths without re-deriving them.
{pkgs, ...}: let
  # ── Charge mode toggle ─────────────────────────────────────────────
  # Switches between full (100%) and balanced (70-80%) FlexiCharger modes.
  lecoo-toggle = pkgs.writeShellScriptBin "lecoo-toggle" ''
    output=$(${pkgs.lecoo-ctrl}/bin/lecoo-ctrl charge 2>/dev/null)
    if echo "$output" | ${pkgs.gnugrep}/bin/grep -q "Full Capacity"; then
      ${pkgs.lecoo-ctrl}/bin/lecoo-ctrl charge balanced >/dev/null 2>&1
      printf '{"text":"","class":"balanced","tooltip":"Charge: Balanced (70-80%%)"}\n'
    else
      ${pkgs.lecoo-ctrl}/bin/lecoo-ctrl charge full >/dev/null 2>&1
      printf '{"text":"","class":"full","tooltip":"Charge: Full (100%%)"}\n'
    fi
  '';

  lecoo-status = pkgs.writeShellScriptBin "lecoo-status" ''
    output=$(${pkgs.lecoo-ctrl}/bin/lecoo-ctrl charge 2>/dev/null)
    if echo "$output" | ${pkgs.gnugrep}/bin/grep -q "Full Capacity"; then
      printf '{"text":"","class":"full","tooltip":"Charge: Full (100%%)"}\n'
    else
      stop=$(echo "$output" | ${pkgs.gnugrep}/bin/grep -oP 'Stop charging at:\s*\K\d+' 2>/dev/null)
      case "$stop" in
        95) printf '{"text":"95","class":"high","tooltip":"Charge: High (90-95%%)"}\n' ;;
        80) printf '{"text":"","class":"balanced","tooltip":"Charge: Balanced (70-80%%)"}\n' ;;
        60) printf '{"text":"60","class":"lifespan","tooltip":"Charge: Lifespan (55-60%%)"}\n' ;;
        50) printf '{"text":"40","class":"desk","tooltip":"Charge: Desk (40-50%%)"}\n' ;;
        *)  printf '{"text":"?","class":"balanced","tooltip":"Charge: Unknown"}\n' ;;
      esac
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
      battery-lecoo
      ;
  };

  home.packages = [
    lecoo-toggle
    lecoo-status
    battery-lecoo
  ];
}
