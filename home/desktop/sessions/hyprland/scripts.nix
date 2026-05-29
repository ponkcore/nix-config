# scripts.nix — Hyprland-session-only helper scripts.
#
# Anything that drives `hyprctl` lives here, not in theme/scripts.nix:
# these toggles only make sense inside a Hyprland session and break
# under any other compositor.
#
# Application toggles (Telegram, Clash Verge) belong here too rather
# than at the host level: they all rely on Hyprland's special-workspace
# mechanism for the hide/show pattern.
{pkgs, ...}: let
  # ── App status probe ───────────────────────────────────────────────
  # Generic waybar exec — emits {text, class} where class is
  # "running" iff a Hyprland client with the given window-class is
  # present (regular workspace OR special:*). Glyph stays in the
  # waybar `format` field so this script just toggles the CSS hook.
  #
  # Background services do not count: e.g. throne-core or telegram
  # background fetchers may stay alive even when no GUI window
  # exists, so probing the GUI class gives the right answer for
  # "is the user-facing app open".
  app-status = pkgs.writeShellScriptBin "app-status" ''
    HYPRCTL="${pkgs.hyprland}/bin/hyprctl"
    JQ="${pkgs.jq}/bin/jq"
    if [ $# -lt 1 ]; then
      echo '{"text":"","class":""}'
      exit 0
    fi
    cls="$1"
    if $HYPRCTL clients -j 2>/dev/null | $JQ -e --arg c "$cls" 'any(.[]; .class == $c)' >/dev/null; then
      echo '{"text":"","class":"running"}'
    else
      echo '{"text":"","class":""}'
    fi
  '';

  # ── Telegram/Ayugram toggle ─────────────────────────────────────────
  # Uses Hyprland special:telegram workspace as hide/show target.
  # No "minimize" in Hyprland — movetoworkspacesilent is the pattern.
  telegram-toggle = pkgs.writeShellScriptBin "telegram-toggle" ''
    HYPRCTL="${pkgs.hyprland}/bin/hyprctl"
    JQ="${pkgs.jq}/bin/jq"

    win=$($HYPRCTL clients -j 2>/dev/null | $JQ -r '.[] | select(.class == "com.ayugram.desktop") | "\(.address) \(.workspace.name)"' 2>/dev/null | head -1)

    AYUGRAM="${pkgs.ayugram-desktop}/bin/AyuGram"

    if [ -z "$win" ]; then
      $AYUGRAM &
      exit 0
    fi

    addr=$(echo "$win" | cut -d' ' -f1)
    ws=$(echo "$win" | cut -d' ' -f2-)

    if [ "$ws" = "special:telegram" ]; then
      $HYPRCTL dispatch movetoworkspace "+0,address:$addr"
    else
      $HYPRCTL dispatch movetoworkspacesilent "special:telegram,address:$addr"
    fi
  '';

  # ── Throne toggle ───────────────────────────────────────────────────
  # Same hide/show pattern as telegram-toggle but parked on
  # special:throne. Mirrors the "minimize to tray" UX without a tray
  # applet (Waybar has no tray module on this host). First click
  # launches the GUI through the throne-launch wrapper (sets
  # QT_PLUGIN_PATH so Kvantum/qt6ct plugins from the user profile
  # are visible to Throne 1.0.13's bundled qtbase-6.11); subsequent
  # clicks toggle visibility. The window class is just `Throne`
  # (capital T) — verified at runtime against `hyprctl clients`.
  throne-toggle = pkgs.writeShellScriptBin "throne-toggle" ''
    HYPRCTL="${pkgs.hyprland}/bin/hyprctl"
    JQ="${pkgs.jq}/bin/jq"

    win=$($HYPRCTL clients -j 2>/dev/null | $JQ -r '.[] | select(.class == "Throne") | "\(.address) \(.workspace.name)"' 2>/dev/null | head -1)

    if [ -z "$win" ]; then
      throne-launch &
      exit 0
    fi

    addr=$(echo "$win" | cut -d' ' -f1)
    ws=$(echo "$win" | cut -d' ' -f2-)

    if [ "$ws" = "special:throne" ]; then
      $HYPRCTL dispatch movetoworkspace "+0,address:$addr"
    else
      $HYPRCTL dispatch movetoworkspacesilent "special:throne,address:$addr"
    fi
  '';

  # ── Spotify toggle ──────────────────────────────────────────────────
  # Same pattern as telegram-toggle / clash-toggle but parked on
  # special:spotify. Spotify has a system-tray icon of its own, but
  # since Waybar carries no tray module on this host the special-
  # workspace toggle drives the entire show/hide UX.
  # Spotify 1.2.74+ runs as a native Wayland client; its app_id is
  # the lowercase string "spotify".
  spotify-toggle = pkgs.writeShellScriptBin "spotify-toggle" ''
    HYPRCTL="${pkgs.hyprland}/bin/hyprctl"
    JQ="${pkgs.jq}/bin/jq"

    win=$($HYPRCTL clients -j 2>/dev/null | $JQ -r '.[] | select(.class == "spotify") | "\(.address) \(.workspace.name)"' 2>/dev/null | head -1)

    SPOTIFY="${pkgs.spotify}/bin/spotify"

    if [ -z "$win" ]; then
      $SPOTIFY &
      exit 0
    fi

    addr=$(echo "$win" | cut -d' ' -f1)
    ws=$(echo "$win" | cut -d' ' -f2-)

    if [ "$ws" = "special:spotify" ]; then
      $HYPRCTL dispatch movetoworkspace "+0,address:$addr"
    else
      $HYPRCTL dispatch movetoworkspacesilent "special:spotify,address:$addr"
    fi
  '';

  # ── Nautilus open (new window each time) ───────────────────────────
  # Unlike the other tray toggles, Nautilus is bound as a "spawn a
  # fresh window" action — file-manager UX is "I want another window
  # to drag/drop into", not "hide/show one canonical window".
  # `--new-window` forces a fresh top-level even when an existing
  # Nautilus instance is alive (DBus-bridged single-instance mode is
  # the default — without the flag the binding would just focus the
  # existing window, which is the wrong UX here). The mkPopup rule
  # for `org.gnome.Nautilus` in session.nix still floats / sizes /
  # centres each new window the same way.
  nautilus-open = pkgs.writeShellScriptBin "nautilus-open" ''
    exec ${pkgs.nautilus}/bin/nautilus --new-window
  '';

  # ── KeePassXC toggle ────────────────────────────────────────────────
  # Same special-workspace pattern as throne-toggle / spotify-toggle.
  # KeePassXC's window class on Wayland is `org.keepassxc.KeePassXC`
  # (verified at runtime against `hyprctl clients`). With
  # MinimizeOnClose=true (our seed default in home/keepassxc.nix) the
  # close button parks the window into the system tray — in that
  # state the class is absent from `hyprctl clients`, so the next
  # click here re-launches keepassxc, which DBus-restores the
  # existing instance instead of spawning a second process.
  keepassxc-toggle = pkgs.writeShellScriptBin "keepassxc-toggle" ''
    HYPRCTL="${pkgs.hyprland}/bin/hyprctl"
    JQ="${pkgs.jq}/bin/jq"

    win=$($HYPRCTL clients -j 2>/dev/null | $JQ -r '.[] | select(.class == "org.keepassxc.KeePassXC") | "\(.address) \(.workspace.name)"' 2>/dev/null | head -1)

    KEEPASSXC="${pkgs.keepassxc}/bin/keepassxc"

    if [ -z "$win" ]; then
      $KEEPASSXC &
      exit 0
    fi

    addr=$(echo "$win" | cut -d' ' -f1)
    ws=$(echo "$win" | cut -d' ' -f2-)

    if [ "$ws" = "special:keepassxc" ]; then
      $HYPRCTL dispatch movetoworkspace "+0,address:$addr"
    else
      $HYPRCTL dispatch movetoworkspacesilent "special:keepassxc,address:$addr"
    fi
  '';

  # ── orbit toggle (bluetooth tab) ────────────────────────────────────
  # Bluetooth tile in Waybar shares the Orbit popup with the Wi-Fi
  # tile — `--tab bluetooth` jumps straight to the Bluetooth panel.
  bluetooth-toggle = pkgs.writeShellScriptBin "bluetooth-toggle" ''
    exec ${pkgs.orbit}/bin/orbit toggle --tab bluetooth
  '';

  # ── orbit toggle (network + bluetooth) ──────────────────────────────
  # Orbit is a layer-shell applet — it does not appear as a Hyprland
  # client and so the special-workspace hide/show pattern other
  # toggle scripts use does not apply. Orbit's own daemon owns the
  # window state; `orbit toggle [--tab <name>]` flips visibility
  # through D-Bus and exits. The HM systemd user service
  # (home/orbit.nix) keeps the daemon alive across waybar reloads
  # and session lifetime.
  #
  # Orbit covers Wi-Fi, Ethernet, Bluetooth, and VPN under the same
  # popup, so both the Waybar wifi tile and the bluetooth tile open
  # the same window with the matching tab pre-selected.
  network-toggle = pkgs.writeShellScriptBin "network-toggle" ''
    exec ${pkgs.orbit}/bin/orbit toggle --tab wifi
  '';

  # ── btop toggle ─────────────────────────────────────────────────────
  # Ghostty popup running btop. Same hide/show contract as the other
  # tray-style toggles: special:btop is the hide target. The window
  # class comes from `ghostty --class=com.mitchellh.ghostty-btop`,
  # which the popup rule in session.nix already targets.
  btop-toggle = pkgs.writeShellScriptBin "btop-toggle" ''
    HYPRCTL="${pkgs.hyprland}/bin/hyprctl"
    JQ="${pkgs.jq}/bin/jq"

    win=$($HYPRCTL clients -j 2>/dev/null | $JQ -r '.[] | select(.class == "com.mitchellh.ghostty-btop") | "\(.address) \(.workspace.name)"' 2>/dev/null | head -1)

    GHOSTTY="${pkgs.ghostty}/bin/ghostty"
    BTOP="${pkgs.btop}/bin/btop"

    if [ -z "$win" ]; then
      $GHOSTTY --class=com.mitchellh.ghostty-btop -e $BTOP &
      exit 0
    fi

    addr=$(echo "$win" | cut -d' ' -f1)
    ws=$(echo "$win" | cut -d' ' -f2-)

    if [ "$ws" = "special:btop" ]; then
      $HYPRCTL dispatch movetoworkspace "+0,address:$addr"
    else
      $HYPRCTL dispatch movetoworkspacesilent "special:btop,address:$addr"
    fi
  '';

  # ── recenter-floating ────────────────────────────────────────────────
  # Walks every floating client and re-centers any whose top-left
  # `at` falls outside the logical rectangle of the monitor that
  # currently hosts its workspace. Used as a manual rescue when
  # Hyprland 0.52.1 mis-recomputes floating-window coordinates after
  # a long idle period (mixed-scale eDP-1 + HDMI-A-1; see
  # journal/2026-05-25 and journal/2026-05-26).
  #
  # Two modes:
  #   recenter-floating         — drift-only: only off-monitor windows
  #   recenter-floating --all   — center every floating window
  #
  # Idempotent: a window already inside its monitor is left alone in
  # the default mode.
  recenter-floating = pkgs.writeShellScriptBin "recenter-floating" ''
    set -euo pipefail
    HYPRCTL="${pkgs.hyprland}/bin/hyprctl"
    JQ="${pkgs.jq}/bin/jq"

    mode="drift"
    if [ "''${1:-}" = "--all" ]; then
      mode="all"
    fi

    monitors=$($HYPRCTL monitors -j)
    clients=$($HYPRCTL clients -j)

    # Build a tab-separated table of floating windows joined with the
    # logical bounds of the monitor hosting their workspace:
    #   addr  ws  cx  cy  cw  ch  mon_x  mon_y  mon_w  mon_h
    # Logical width/height = physical / scale.
    rows=$(echo "$clients" | $JQ -r --argjson mons "$monitors" '
      [
        $mons[] | {
          id: .id,
          x: .x,
          y: .y,
          w: (.width / .scale | floor),
          h: (.height / .scale | floor)
        }
      ] as $mlist
      | .[]
      | select(.floating == true)
      | . as $c
      | ($mlist[] | select(.id == $c.monitor)) as $m
      | [
          $c.address,
          ($c.workspace.id | tostring),
          ($c.at[0] | tostring),
          ($c.at[1] | tostring),
          ($c.size[0] | tostring),
          ($c.size[1] | tostring),
          ($m.x | tostring),
          ($m.y | tostring),
          ($m.w | tostring),
          ($m.h | tostring)
        ]
      | @tsv
    ')

    moved=0
    skipped=0
    cmds=""
    while IFS=$'\t' read -r addr ws cx cy cw ch mx my mw mh; do
      [ -z "$addr" ] && continue
      out_of_bounds=0
      if [ "$cx" -lt "$mx" ] || [ "$cy" -lt "$my" ]; then
        out_of_bounds=1
      fi
      right=$((mx + mw))
      bottom=$((my + mh))
      if [ "$cx" -ge "$right" ] || [ "$cy" -ge "$bottom" ]; then
        out_of_bounds=1
      fi

      if [ "$mode" = "drift" ] && [ "$out_of_bounds" -eq 0 ]; then
        skipped=$((skipped + 1))
        continue
      fi

      # Center in the logical monitor rectangle.
      tx=$((mx + (mw - cw) / 2))
      ty=$((my + (mh - ch) / 2))
      cmds="''${cmds}dispatch movewindowpixel exact $tx $ty,address:$addr ; "
      moved=$((moved + 1))
    done <<<"$rows"

    if [ "$moved" -eq 0 ]; then
      echo "recenter-floating: nothing to move ($skipped already in bounds)"
      exit 0
    fi

    # Strip trailing " ; " before passing to --batch.
    cmds=''${cmds% ; }
    $HYPRCTL --batch "$cmds" >/dev/null
    echo "recenter-floating: moved=$moved skipped=$skipped mode=$mode"
  '';

  # ── pwvucontrol toggle ──────────────────────────────────────────────
  # GTK4 / libadwaita PipeWire volume mixer. Same hide/show contract as
  # the other tray-style toggles: special:audio is the hide target,
  # first click launches, subsequent clicks toggle visibility.
  # Native Wayland client; app_id is "com.saivert.pwvucontrol".
  pwvucontrol-toggle = pkgs.writeShellScriptBin "pwvucontrol-toggle" ''
    HYPRCTL="${pkgs.hyprland}/bin/hyprctl"
    JQ="${pkgs.jq}/bin/jq"

    win=$($HYPRCTL clients -j 2>/dev/null | $JQ -r '.[] | select(.class == "com.saivert.pwvucontrol") | "\(.address) \(.workspace.name)"' 2>/dev/null | head -1)

    PWVU="${pkgs.pwvucontrol}/bin/pwvucontrol"

    if [ -z "$win" ]; then
      $PWVU &
      exit 0
    fi

    addr=$(echo "$win" | cut -d' ' -f1)
    ws=$(echo "$win" | cut -d' ' -f2-)

    if [ "$ws" = "special:audio" ]; then
      $HYPRCTL dispatch movetoworkspace "+0,address:$addr"
    else
      $HYPRCTL dispatch movetoworkspacesilent "special:audio,address:$addr"
    fi
  '';
in {
  _module.args = {
    inherit
      app-status
      telegram-toggle
      throne-toggle
      spotify-toggle
      keepassxc-toggle
      nautilus-open
      bluetooth-toggle
      network-toggle
      pwvucontrol-toggle
      btop-toggle
      recenter-floating
      ;
  };

  home.packages = [
    app-status
    telegram-toggle
    throne-toggle
    spotify-toggle
    keepassxc-toggle
    nautilus-open
    bluetooth-toggle
    network-toggle
    pwvucontrol-toggle
    btop-toggle
    recenter-floating
  ];
}
