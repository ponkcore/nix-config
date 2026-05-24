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
      bluetooth-toggle
      network-toggle
      pwvucontrol-toggle
      btop-toggle
      ;
  };

  home.packages = [
    app-status
    telegram-toggle
    throne-toggle
    spotify-toggle
    bluetooth-toggle
    network-toggle
    pwvucontrol-toggle
    btop-toggle
  ];
}
