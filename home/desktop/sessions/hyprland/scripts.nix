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
  # Generic app-status probe — emits {text, class} where class is
  # "running" iff a Hyprland client with the given window-class is
  # present (regular workspace OR special:*).
  #
  # The expensive part is `hyprctl clients -j`. Running it every 2 s
  # per app wasted CPU while idle. The app-status-daemon below
  # listens to Hyprland's event socket and writes cached JSON files under
  # $XDG_RUNTIME_DIR. app-status only
  # reads that cache; it falls back to a direct probe if the daemon is
  # not ready yet.
  app-status = pkgs.writeShellScriptBin "app-status" ''
    HYPRCTL="${pkgs.hyprland}/bin/hyprctl"
    JQ="${pkgs.jq}/bin/jq"
    COREUTILS="${pkgs.coreutils}/bin"

    if [ $# -lt 1 ]; then
      echo '{"text":"","class":""}'
      exit 0
    fi

    cls="$1"
    key=$(printf '%s' "$cls" | "$COREUTILS/tr" -c 'A-Za-z0-9_.-' '_')
    cache="''${XDG_RUNTIME_DIR:-/tmp}/app-status/$key.json"

    if [ -r "$cache" ]; then
      "$COREUTILS/cat" "$cache"
      exit 0
    fi

    if $HYPRCTL clients -j 2>/dev/null | $JQ -e --arg c "$cls" 'any(.[]; .class == $c)' >/dev/null; then
      echo '{"text":"","class":"running"}'
    else
      echo '{"text":"","class":""}'
    fi
  '';

  # ── App status daemon ──────────────────────────────────────────────
  # One Hyprland event-socket listener for all app-status consumers. This
  # replaces four independent 2-second polling loops with event-driven
  # cache updates. Visual behaviour stays the same: same glyphs, same
  # `.running` CSS class, same glow — only the update source changes.
  app-status-daemon = pkgs.writeShellScriptBin "app-status-daemon" ''
    set -eu

    HYPRCTL="${pkgs.hyprland}/bin/hyprctl"
    JQ="${pkgs.jq}/bin/jq"
    SOCAT="${pkgs.socat}/bin/socat"
    COREUTILS="${pkgs.coreutils}/bin"
    PROCPS="${pkgs.procps}/bin"

    runtime="''${XDG_RUNTIME_DIR:-/tmp}/app-status"
    classes='com.ayugram.desktop spotify Throne'

    write_status() {
      cls="$1"
      state="$2"
      key=$(printf '%s' "$cls" | "$COREUTILS/tr" -c 'A-Za-z0-9_.-' '_')
      printf '{"text":"","class":"%s"}\n' "$state" > "$runtime/$key.json"
    }

    refresh() {
      "$COREUTILS/mkdir" -p "$runtime"
      clients=$($HYPRCTL clients -j 2>/dev/null || printf '[]')

      for cls in $classes; do
        if printf '%s' "$clients" | $JQ -e --arg c "$cls" 'any(.[]; .class == $c)' >/dev/null; then
          write_status "$cls" running
        else
          write_status "$cls" ""
        fi
      done

    }

    if [ "''${1:-}" = "--oneshot" ]; then
      refresh
      exit 0
    fi

    if [ -z "''${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
      for _ in $(${pkgs.coreutils}/bin/seq 1 150); do
        HYPRLAND_INSTANCE_SIGNATURE=$($HYPRCTL instances -j 2>/dev/null | $JQ -r '.[0].instance // empty' 2>/dev/null || true)
        if [ -n "$HYPRLAND_INSTANCE_SIGNATURE" ]; then
          export HYPRLAND_INSTANCE_SIGNATURE
          break
        fi
        "$COREUTILS/sleep" 0.2
      done
    fi

    while [ -z "''${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; do
      "$COREUTILS/sleep" 0.2
    done

    socket="''${XDG_RUNTIME_DIR:-/tmp}/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"
    until [ -S "$socket" ]; do
      "$COREUTILS/sleep" 0.2
    done

    refresh

    while true; do
      $SOCAT -u UNIX-CONNECT:"$socket" - 2>/dev/null | while IFS= read -r event; do
        case "$event" in
          openwindow*|closewindow*) refresh ;;
        esac
      done
      "$COREUTILS/sleep" 1
    done
  '';

  # ── Throne VPN status ──────────────────────────────────────────────
  # Throne status helper. Checks the throne-tun interface
  # first (sing-box TUN mode), then falls back to the app-status
  # cache for the window-running state. TUN state changes don't
  # emit Hyprland events, so this stays polling-based.
  #
  # Classes:
  #   vpn-active — throne-tun interface exists (tunnel is up)
  #   running    — Throne window is open but TUN is down
  #   ""         — neither
  throne-status = pkgs.writeShellScriptBin "throne-status" ''
    IP="${pkgs.iproute2}/bin/ip"
    GREP="${pkgs.gnugrep}/bin/grep"
    COREUTILS="${pkgs.coreutils}/bin"

    # Check TUN interface first — takes priority. TUN devices report
    # state UNKNOWN (no link layer), so we check for the interface's
    # existence + UP flag in the angle-bracket flags, not "state UP".
    if $IP link show throne-tun 2>/dev/null | $GREP -q '<.*UP.*>'; then
      # Power-state-aware class so CSS can render different visuals:
      #   eco / battery → static yellow (subtle, power-conscious)
      #   AC            → animated gradient shimmer (yellow ↔ magenta)
      eco_on=""
      if [ -f /var/lib/lecoo-eco/state-on ]; then
        eco_on="1"
      fi
      ac_on=$(cat /sys/class/power_supply/ADP1/online 2>/dev/null || echo 0)

      if [ -n "$eco_on" ] || [ "$ac_on" != "1" ]; then
        echo '{"text":"","class":"vpn-active-battery"}'
      else
        echo '{"text":"","class":"vpn-active-ac"}'
      fi
      exit 0
    fi

    # Fall back to app-status cache for window-running state.
    cls="Throne"
    key=$(printf '%s' "$cls" | "$COREUTILS/tr" -c 'A-Za-z0-9_.-' '_')
    cache="''${XDG_RUNTIME_DIR:-/tmp}/app-status/$key.json"
    if [ -r "$cache" ]; then
      "$COREUTILS/cat" "$cache"
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
  # applet. First click
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
  # the special-
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

  keepassxc-launch = pkgs.writeShellScript "keepassxc-launch" ''
    export QT_STYLE_OVERRIDE=kvantum
    unset QT_QPA_PLATFORMTHEME
    exec ${pkgs.keepassxc}/bin/keepassxc "$@"
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

    KEEPASSXC="${keepassxc-launch}"

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
      app-status-daemon
      telegram-toggle
      throne-toggle
      throne-status
      spotify-toggle
      keepassxc-toggle
      nautilus-open
      pwvucontrol-toggle
      btop-toggle
      ;
  };

  systemd.user.services.app-status-daemon = {
    Unit = {
      Description = "Cache Hyprland app status";
      After = ["graphical-session.target" "wayland-wm@Hyprland.service"];
      PartOf = ["graphical-session.target"];
    };
    Service = {
      ExecStart = "${app-status-daemon}/bin/app-status-daemon";
      Restart = "always";
      RestartSec = 3;
    };
    Install.WantedBy = ["graphical-session.target"];
  };

  home.packages = [
    app-status
    app-status-daemon
    telegram-toggle
    throne-toggle
    throne-status
    spotify-toggle
    keepassxc-toggle
    nautilus-open
    pwvucontrol-toggle
    btop-toggle
  ];
}
