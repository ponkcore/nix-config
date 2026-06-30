# scripts.nix — universal, session-agnostic helper scripts.
#
# Only scripts that hold across any compositor and any host live here.
# Session-specific scripts (toggles that drive `hyprctl`) live in
# home/desktop/sessions/<name>/scripts.nix; host-specific scripts (Lecoo
# EC charge mode) live in hosts/<name>/home/scripts.nix.
#
# Adding a new universal script: define here, expose via _module.args
# so consumer modules (waybar, mako-styled widgets) can embed the
# absolute /nix/store path without re-deriving it.
{pkgs, ...}: let
  # ── Notification (mako) ─────────────────────────────────────────────
  notification-toggle = pkgs.writeShellScriptBin "notification-toggle" ''
    current=$(${pkgs.mako}/bin/makoctl mode 2>/dev/null || echo "default")
    if [ "$current" = "do-not-disturb" ]; then
      ${pkgs.mako}/bin/makoctl mode default
      printf '{"text":"ON","class":"default","tooltip":"Notifications: ON"}\n'
    else
      ${pkgs.mako}/bin/makoctl mode -a do-not-disturb
      printf '{"text":"DND","class":"dnd","tooltip":"Notifications: OFF (DND)"}\n'
    fi
  '';

  notification-status = pkgs.writeShellScriptBin "notification-status" ''
    current=$(${pkgs.mako}/bin/makoctl mode 2>/dev/null || echo "default")
    if [ "$current" = "do-not-disturb" ]; then
      printf '{"text":"DND","class":"dnd","tooltip":"Notifications: OFF (DND)"}\n'
    else
      printf '{"text":"ON","class":"default","tooltip":"Notifications: ON"}\n'
    fi
  '';

  # ── CPU + memory waybar feed ────────────────────────────────────────
  # Custom waybar module producing JSON with an empty `text` and a
  # tooltip line carrying CPU avg usage and RAM used/total. State
  # for the CPU delta lives in /tmp; first call returns 0%.
  cpu-mem = pkgs.writeShellScriptBin "cpu-mem" ''
    set -u
    PREV="/tmp/waybar-cpumem-prev-''${USER}"

    # /proc/stat first line: "cpu user nice system idle iowait irq softirq steal ..."
    read_total_idle() {
      ${pkgs.gawk}/bin/awk 'NR==1 {
        idle = $5 + $6
        total = 0
        for (i = 2; i <= NF; i++) total += $i
        printf "%d %d", total, idle
        exit
      }' /proc/stat
    }

    CUR=$(read_total_idle)
    USAGE=0
    if [ -f "$PREV" ]; then
      P=$(cat "$PREV")
      PT=$(printf "%s" "$P" | ${pkgs.gawk}/bin/awk '{print $1}')
      PI=$(printf "%s" "$P" | ${pkgs.gawk}/bin/awk '{print $2}')
      CT=$(printf "%s" "$CUR" | ${pkgs.gawk}/bin/awk '{print $1}')
      CI=$(printf "%s" "$CUR" | ${pkgs.gawk}/bin/awk '{print $2}')
      DT=$((CT - PT))
      DI=$((CI - PI))
      if [ "$DT" -gt 0 ]; then
        USAGE=$(( (100 * (DT - DI)) / DT ))
        if [ "$USAGE" -lt 0 ]; then USAGE=0; fi
        if [ "$USAGE" -gt 99 ]; then USAGE=99; fi
      fi
    fi
    printf "%s\n" "$CUR" > "$PREV"

    # /proc/meminfo: MemTotal, MemAvailable in kB
    MT=$(${pkgs.gawk}/bin/awk '/^MemTotal:/ {print $2; exit}' /proc/meminfo)
    MA=$(${pkgs.gawk}/bin/awk '/^MemAvailable:/ {print $2; exit}' /proc/meminfo)
    MU=$((MT - MA))
    RAM_PCT=$(( 100 * MU / MT ))
    if [ "$RAM_PCT" -gt 99 ]; then RAM_PCT=99; fi
    RAM_USED=$(${pkgs.gawk}/bin/awk -v k=$MU 'BEGIN{ printf "%.1f", k/1048576 }')
    RAM_TOT=$(${pkgs.gawk}/bin/awk -v k=$MT 'BEGIN{ printf "%.1f", k/1048576 }')

    # Tooltip uses Nerd Font glyphs and the same `N%glyph|N%glyph`
    # layout as the battery widget (hosts/lecoo/home/scripts.nix):
    #    nf-oct-cpu       (U+F4BC) — CPU avg usage
    #    nf-fa-memory     (U+EFC5) — RAM usage
    TOOLTIP=$(printf '\uf4bc %02d%% | \uefc5 %02d%%' "''${USAGE}" "''${RAM_PCT}")
    TEXT="$TOOLTIP"
    ${pkgs.jq}/bin/jq -cRn --arg t "$TEXT" --arg tip "$TOOLTIP" '{text:$t, tooltip:$tip}'
  '';

  # ── Volume status (waybar custom/volume) ───────────────────────────
  # Pango markup: icon in CommitMono, value in DepartureMono (from `*`).
  # Capped at 99, zero-padded to 2 digits for stable bar width.
  volume-status = pkgs.writeShellScriptBin "volume-status" ''
    VOL=$(${pkgs.pamixer}/bin/pamixer --get-volume 2>/dev/null || echo 0)
    MUTED=$(${pkgs.pamixer}/bin/pamixer --get-mute 2>/dev/null || echo "false")

    [ "$VOL" -gt 99 ] && VOL=99

    if [ "$MUTED" = "true" ]; then
      ICON="󰖁"
    elif [ "$VOL" -gt 50 ]; then
      ICON="󰕾"
    elif [ "$VOL" -gt 25 ]; then
      ICON="󰖀"
    else
      ICON="󰕿"
    fi

    TEXT="<span font_family='CommitMono Nerd Font Propo'>$ICON</span> $(printf '%02d' "$VOL")%"
    ${pkgs.jq}/bin/jq -cn --arg t "$TEXT" '{text:$t, tooltip:false}'
  '';

  # ── Brightness status (waybar custom/brightness) ───────────────────
  # Pango markup: icon in CommitMono, value in DepartureMono (from `*`).
  # Capped at 99, zero-padded to 2 digits for stable bar width.
  brightness-status = pkgs.writeShellScriptBin "brightness-status" ''
    BRIGHT=$(cat /sys/class/backlight/amdgpu_bl1/brightness 2>/dev/null || echo 0)
    MAX=$(cat /sys/class/backlight/amdgpu_bl1/max_brightness 2>/dev/null || echo 1)
    PCT=$(( 100 * BRIGHT / MAX ))
    [ "$PCT" -gt 99 ] && PCT=99

    TEXT="<span font_family='CommitMono Nerd Font Propo' weight='heavy'>󰃟</span> $(printf '%02d' "$PCT")%"
    ${pkgs.jq}/bin/jq -cn --arg t "$TEXT" '{text:$t, tooltip:false}'
  '';

  # ── NixOS update check ─────────────────────────────────────────────
  # Compares locked rev against latest nixpkgs remote.
  # Caches result for 1 hour to avoid expensive network calls on every
  # waybar refresh.
  update-check = pkgs.writeShellScriptBin "update-check" ''
    cache_file="/tmp/nixos-update-check"
    cache_ttl=3600

    if [ -f "$cache_file" ]; then
        cache_age=$(( $(date +%s) - $(stat -c %Y "$cache_file" 2>/dev/null || echo 0) ))
        if [ "$cache_age" -lt "$cache_ttl" ]; then
            cat "$cache_file"
            exit 0
        fi
    fi

    locked=$(${pkgs.nix}/bin/nix flake metadata /etc/nixos --json 2>/dev/null | ${pkgs.jq}/bin/jq -r '.locks.nodes.nixpkgs.locked.rev' 2>/dev/null || echo "")
    latest=$(${pkgs.nix}/bin/nix flake metadata github:NixOS/nixpkgs/nixos-26.05 --json 2>/dev/null | ${pkgs.jq}/bin/jq -r '.revision' 2>/dev/null || echo "")

    if [ -n "$locked" ] && [ -n "$latest" ] && [ "$locked" != "$latest" ]; then
        result='{"text":"upd","class":"has-updates","tooltip":"NixOS update available"}'
    else
        result='{"text":"","class":"updated","tooltip":"System is up to date"}'
    fi

    echo "$result" > "$cache_file"
    echo "$result"
  '';
in {
  # Expose every script as a function arg to other theme modules.
  _module.args = {
    inherit
      notification-toggle
      notification-status
      update-check
      cpu-mem
      volume-status
      brightness-status
      ;
  };

  home.packages = [
    notification-toggle
    notification-status
    update-check
    cpu-mem
    volume-status
    brightness-status
  ];
}
