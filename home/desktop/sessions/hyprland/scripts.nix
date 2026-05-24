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
  # Background services do not count: clash-verge-service is always
  # alive even when no GUI window exists, so probing the GUI class
  # gives the right answer for "is the user-facing app open".
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

  # ── adw-network toggle ──────────────────────────────────────────────
  # Same hide/show contract as bluetooth-toggle. app_id comes from the
  # upstream .desktop StartupWMClass=com.github.adw-network.
  network-toggle = pkgs.writeShellScriptBin "network-toggle" ''
    HYPRCTL="${pkgs.hyprland}/bin/hyprctl"
    JQ="${pkgs.jq}/bin/jq"

    win=$($HYPRCTL clients -j 2>/dev/null | $JQ -r '.[] | select(.class == "com.github.adw-network") | "\(.address) \(.workspace.name)"' 2>/dev/null | head -1)

    ADW="${pkgs.adw-network}/bin/adwaita-network"

    if [ -z "$win" ]; then
      $ADW &
      exit 0
    fi

    addr=$(echo "$win" | cut -d' ' -f1)
    ws=$(echo "$win" | cut -d' ' -f2-)

    if [ "$ws" = "special:network" ]; then
      $HYPRCTL dispatch movetoworkspace "+0,address:$addr"
    else
      $HYPRCTL dispatch movetoworkspacesilent "special:network,address:$addr"
    fi
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
      clash-toggle
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
    clash-toggle
    spotify-toggle
    bluetooth-toggle
    network-toggle
    pwvucontrol-toggle
    btop-toggle
  ];
}
