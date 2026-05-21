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

  # ── Clash Verge toggle ──────────────────────────────────────────────
  # Same hide/show pattern as telegram-toggle but parked on
  # special:clash. Mirrors the "minimize to tray" UX without a tray
  # applet (Waybar has no tray module on this host). First click
  # launches the GUI; subsequent clicks toggle visibility.
  clash-toggle = pkgs.writeShellScriptBin "clash-toggle" ''
    HYPRCTL="${pkgs.hyprland}/bin/hyprctl"
    JQ="${pkgs.jq}/bin/jq"

    win=$($HYPRCTL clients -j 2>/dev/null | $JQ -r '.[] | select(.class == "clash-verge") | "\(.address) \(.workspace.name)"' 2>/dev/null | head -1)

    CLASH="${pkgs.clash-verge-rev}/bin/clash-verge"

    if [ -z "$win" ]; then
      $CLASH &
      exit 0
    fi

    addr=$(echo "$win" | cut -d' ' -f1)
    ws=$(echo "$win" | cut -d' ' -f2-)

    if [ "$ws" = "special:clash" ]; then
      $HYPRCTL dispatch movetoworkspace "+0,address:$addr"
    else
      $HYPRCTL dispatch movetoworkspacesilent "special:clash,address:$addr"
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

  # ── adw-bluetooth toggle ────────────────────────────────────────────
  # GNOME-inspired GTK4 Bluetooth manager. Same hide/show contract as
  # the other tray-style toggles: special:bluetooth is the hide target,
  # first click launches, subsequent clicks toggle visibility.
  # Native Wayland client; app_id is "com.ezratweaver.AdwBluetooth".
  bluetooth-toggle = pkgs.writeShellScriptBin "bluetooth-toggle" ''
    HYPRCTL="${pkgs.hyprland}/bin/hyprctl"
    JQ="${pkgs.jq}/bin/jq"

    win=$($HYPRCTL clients -j 2>/dev/null | $JQ -r '.[] | select(.class == "com.ezratweaver.AdwBluetooth") | "\(.address) \(.workspace.name)"' 2>/dev/null | head -1)

    ADW="${pkgs.adw-bluetooth}/bin/adw-bluetooth"

    if [ -z "$win" ]; then
      $ADW &
      exit 0
    fi

    addr=$(echo "$win" | cut -d' ' -f1)
    ws=$(echo "$win" | cut -d' ' -f2-)

    if [ "$ws" = "special:bluetooth" ]; then
      $HYPRCTL dispatch movetoworkspace "+0,address:$addr"
    else
      $HYPRCTL dispatch movetoworkspacesilent "special:bluetooth,address:$addr"
    fi
  '';
in {
  _module.args = {
    inherit
      telegram-toggle
      clash-toggle
      spotify-toggle
      bluetooth-toggle
      ;
  };

  home.packages = [
    telegram-toggle
    clash-toggle
    spotify-toggle
    bluetooth-toggle
  ];
}
