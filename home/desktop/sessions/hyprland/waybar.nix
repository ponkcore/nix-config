# waybar.nix — Hyprland-session waybar fragment.
#
# Provides configs for the slots that the universal theme/waybar
# layout reserves for an active Hyprland session:
#   - hyprland/workspaces  (Hyprland IPC workspaces module)
#   - custom/telegram      (drives the telegram-toggle script)
#   - custom/spotify       (drives the spotify-toggle script)
#   - custom/throne        (drives the throne-toggle script)
#   - custom/keepassxc     (drives the keepassxc-toggle script)
#   - custom/bluetooth     (drives the bluetooth-toggle script)
#   - network              (Hyprland on-click → network-toggle)
#
# Imported by home/desktop/sessions/hyprland/default.nix; never
# imported on hosts that do not run Hyprland.
{
  lib,
  app-status,
  app-status-daemon,
  telegram-toggle,
  throne-toggle,
  spotify-toggle,
  keepassxc-toggle,
  bluetooth-toggle,
  network-toggle,
  pwvucontrol-toggle,
  btop-toggle,
  pkgs,
  ...
}: let
  waybar-with-hyprland-env = pkgs.writeShellScript "waybar-with-hyprland-env" ''
    set -u

    HYPRCTL="${pkgs.hyprland}/bin/hyprctl"
    JQ="${pkgs.jq}/bin/jq"

    # UWSM imports HYPRLAND_INSTANCE_SIGNATURE and WAYLAND_DISPLAY into
    # the systemd user manager asynchronously. On cold boot, waybar can
    # be started after WAYLAND_DISPLAY exists but before the Hyprland
    # instance signature reaches the manager; then waybar's
    # hyprland/workspaces module never enables IPC. Query the running
    # compositor directly and export both variables before exec.
    for _ in $(${pkgs.coreutils}/bin/seq 1 150); do
      instance_json="$($HYPRCTL instances -j 2>/dev/null || printf '[]')"
      HYPRLAND_INSTANCE_SIGNATURE="$(printf '%s' "$instance_json" | $JQ -r '.[0].instance // empty')"
      WAYLAND_DISPLAY="$(printf '%s' "$instance_json" | $JQ -r '.[0].wl_socket // empty')"

      if [ -n "$HYPRLAND_INSTANCE_SIGNATURE" ] && [ -n "$WAYLAND_DISPLAY" ]; then
        export HYPRLAND_INSTANCE_SIGNATURE WAYLAND_DISPLAY
        break
      fi

      ${pkgs.coreutils}/bin/sleep 0.2
    done

    exec ${pkgs.waybar}/bin/waybar
  '';
in {
  # Waybar must start after Hyprland IPC is fully ready, not
  # merely after graphical-session.target. Without this, the
  # hyprland/workspaces module subscribes to a compositor whose
  # event loop is not yet dispatching — the subscription silently
  # dies, leaving a static workspace strip. Cf. lesson 0005.
  systemd.user.services.waybar = {
    Unit = {
      After = ["graphical-session.target" "wayland-wm@Hyprland.service" "app-status-daemon.service"];
      Wants = ["app-status-daemon.service"];
    };
    Service.ExecStartPre = "${pkgs.coreutils}/bin/timeout 30 ${pkgs.writeShellScript "waybar-wait-hyprland" ''
      # Poll the main Hyprland IPC socket until it responds.
      # This confirms the compositor event loop is alive at
      # the core IPC layer, but socket2 (the event stream
      # that waybar's hyprland/workspaces module subscribes
      # to) may need additional warm-up after the main socket
      # goes live. Cf. lesson 0005.
      until ${pkgs.hyprland}/bin/hyprctl monitors >/dev/null 2>&1; do
        ${pkgs.coreutils}/bin/sleep 0.2
      done
      # Give socket2 a moment to start dispatching before
      # waybar subscribes. Without this, the subscription
      # can silently die, leaving a frozen workspace strip
      # that no amount of nixos-rebuild will fix — only a
      # manual `systemctl --user restart waybar.service`.
      ${pkgs.coreutils}/bin/sleep 0.5
      ${app-status-daemon}/bin/app-status-daemon --oneshot >/dev/null 2>&1 || true
    ''}";
    Service.ExecStart = lib.mkForce "${waybar-with-hyprland-env}";
  };

  # After any rebuild that changes hyprland.conf, restart waybar so
  # its Hyprland IPC subscription does not desync from the freshly-
  # reloaded compositor. The checksum gate avoids a restart when
  # only unrelated files changed. Cf. lesson 0005.
  home.activation.restartWaybarOnHyprlandChange = lib.hm.dag.entryAfter ["writeBoundary"] ''
    if [ -f ~/.config/hypr/hyprland.conf ]; then
      NEW=$(${pkgs.coreutils}/bin/sha256sum ~/.config/hypr/hyprland.conf | ${pkgs.coreutils}/bin/cut -d' ' -f1)
      CACHE=~/.cache/hyprland-conf-sha256
      OLD=$(${pkgs.coreutils}/bin/cat "$CACHE" 2>/dev/null || echo "")
      if [ "$NEW" != "$OLD" ]; then
        echo "$NEW" > "$CACHE"
        # Give Hyprland a moment to process the reload before
        # restarting waybar. The HM activation writes
        # hyprland.conf, then Hyprland's inotify fires and
        # reloads the config. A short delay ensures waybar
        # connects to the fresh event stream.
        (${pkgs.coreutils}/bin/sleep 2 && $DRY_RUN_CMD ${pkgs.systemd}/bin/systemctl --user restart waybar.service) &
      fi
    fi
  '';

  programs.waybar.settings.mainBar = {
    "hyprland/workspaces" = {
      on-click = "activate";
      cursor = true;
      format = "{icon}";
      format-icons = {
        "1" = "1";
        "2" = "2";
        "3" = "3";
        "4" = "4";
        "5" = "5";
        "6" = "6";
        "7" = "7";
        "8" = "8";
        "9" = "9";
      };
      persistent-workspaces = {
        "1" = [];
        "2" = [];
        "3" = [];
        "4" = [];
        "5" = [];
        "6" = [];
        "7" = [];
        "8" = [];
        "9" = [];
      };
    };

    "custom/telegram" = {
      format = "<span weight='heavy'></span>";
      exec = "${app-status}/bin/app-status com.ayugram.desktop";
      return-type = "json";
      signal = 8;
      on-click = "${telegram-toggle}/bin/telegram-toggle";
      tooltip = false;
    };

    "custom/spotify" = {
      format = "<span weight='heavy'></span>";
      exec = "${app-status}/bin/app-status spotify";
      return-type = "json";
      signal = 8;
      on-click = "${spotify-toggle}/bin/spotify-toggle";
      tooltip = false;
    };

    "custom/throne" = {
      # Glyph: nf-md-shield_lock — Throne is a VPN / Xray proxy GUI;
      # the shield-with-lock reads as "secured tunnel" alongside the
      # surrounding tray icons. Was previously fa-key; that glyph
      # moved to custom/keepassxc where it is a more accurate fit.
      # CSS hook `#custom-throne.running` handles active-state tint
      # via the JSON class app-status returns. Throne reports its
      # window class as `Throne` (capital T) — verified at runtime
      # against `hyprctl clients`.
      format = "<span weight='heavy'>󰦝</span>";
      exec = "${app-status}/bin/app-status Throne";
      return-type = "json";
      signal = 8;
      on-click = "${throne-toggle}/bin/throne-toggle";
      tooltip = false;
    };

    "custom/keepassxc" = {
      # Glyph: fa-key (), inherited from the previous custom/throne
      # slot — reads as "password manager" / "credentials". The
      # window class on Wayland is the lowercase reverse-DNS
      # `org.keepassxc.KeePassXC`, verified at runtime against
      # `hyprctl clients`. CSS hook `#custom-keepassxc.running`
      # handles the active-state pulse via the JSON class
      # app-status returns when a KeePassXC window is present.
      # Note: with MinimizeOnClose=true (our seed default in
      # home/keepassxc.nix) the close button parks the window into
      # the tray — in that state the class is absent from
      # `hyprctl clients`, so the next click re-launches keepassxc,
      # which DBus-restores the existing instance instead of
      # spawning a second process.
      format = "<span weight='heavy'></span>";
      exec = "${app-status}/bin/app-status org.keepassxc.KeePassXC";
      return-type = "json";
      signal = 8;
      on-click = "${keepassxc-toggle}/bin/keepassxc-toggle";
      tooltip = false;
    };

    "custom/bluetooth" = {
      format = "<span weight='heavy'></span>";
      on-click = "${bluetooth-toggle}/bin/bluetooth-toggle";
      tooltip = false;
    };

    # Hyprland-aware override of the universal `network` slot:
    # keep all formatting / icons from theme/waybar/default.nix and
    # only attach a hide/show on-click via Hyprland special-workspace
    # IPC (mirror of custom/bluetooth).
    "network" = {
      on-click = "${network-toggle}/bin/network-toggle";
    };

    # Hyprland-aware override of the universal `pulseaudio#output`
    # slot: keep formatting / icons / scroll behaviour from
    # theme/waybar/default.nix and attach a hide/show on-click that
    # toggles pwvucontrol via Hyprland special-workspace IPC.
    # Right-click stays as `pamixer -t` (mute) from the universal
    # config.
    "pulseaudio#output" = {
      on-click = "${pwvucontrol-toggle}/bin/pwvucontrol-toggle";
    };

    # Hyprland-aware override of the universal `custom/cpu` slot:
    # replace the launch-only on-click with the special-workspace
    # hide/show toggle on special:btop. mkForce because the universal
    # theme/waybar already sets on-click to a plain ghostty launcher.
    "custom/cpu" = {
      on-click = lib.mkForce "${btop-toggle}/bin/btop-toggle";
    };
  };
}
