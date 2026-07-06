# waybar.nix — Hyprland-session waybar fragment.
#
# Provides configs for the slots that the universal theme/waybar
# layout reserves for an active Hyprland session:
#   - hyprland/workspaces  (Hyprland IPC workspaces module)
#   - custom/telegram      (drives the telegram-toggle script)
#   - custom/spotify       (drives the spotify-toggle script)
#   - custom/throne        (drives the throne-toggle script, VPN-aware)
#   - custom/bluetooth     (drives the bluetooth-toggle script)
#   - network              (Hyprland on-click → network-toggle)
#
# Imported by home/desktop/sessions/hyprland/default.nix; never
# imported on hosts that do not run Hyprland.
{
  lib,
  app-status,
  telegram-toggle,
  throne-toggle,
  throne-status,
  spotify-toggle,
  bluetooth-toggle,
  network-toggle,
  pwvucontrol-toggle,
  btop-toggle,
  theme,
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
    #
    # We also wait for the IPC socket2 file to appear — even with the
    # signature, waybar's hyprland/workspaces module silently skips IPC
    # if the socket isn't ready yet, and never retries. A 1-second
    # settle delay after finding the signature ensures the compositor's
    # event loop is dispatching before waybar connects.
    for _ in $(${pkgs.coreutils}/bin/seq 1 150); do
      instance_json="$($HYPRCTL instances -j 2>/dev/null || printf '[]')"
      HYPRLAND_INSTANCE_SIGNATURE="$(printf '%s' "$instance_json" | $JQ -r '.[0].instance // empty')"
      WAYLAND_DISPLAY="$(printf '%s' "$instance_json" | $JQ -r '.[0].wl_socket // empty')"

      if [ -n "$HYPRLAND_INSTANCE_SIGNATURE" ] && [ -n "$WAYLAND_DISPLAY" ]; then
        SOCKET="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"
        if [ -S "$SOCKET" ]; then
          export HYPRLAND_INSTANCE_SIGNATURE WAYLAND_DISPLAY
          # Settle delay: socket exists but compositor's event loop
          # may not be dispatching yet. 1 s is cheap insurance against
          # waybar's silent no-IPC fallback.
          ${pkgs.coreutils}/bin/sleep 1
          break
        fi
      fi

      ${pkgs.coreutils}/bin/sleep 0.2
    done

    exec ${pkgs.waybar}/bin/waybar
  '';
in {
  # Waybar must start with Hyprland's runtime environment, not just
  # after the user session target. On cold boot UWSM can import
  # HYPRLAND_INSTANCE_SIGNATURE into the systemd user manager after
  # waybar is already eligible to start; without the signature,
  # hyprland/workspaces skips IPC entirely. Cf. lesson 0005.
  systemd.user.services.waybar = {
    Unit = {
      After = ["graphical-session.target" "wayland-wm@Hyprland.service" "app-status-daemon.service"];
      Wants = ["app-status-daemon.service"];
      Conflicts = ["quickshell.service"];
    };
    Service = {
      ExecStart = lib.mkForce "${waybar-with-hyprland-env}";
      # ExecStartPre poll: wait for Hyprland instance to be ready
      # before launching the wrapper. Belt-and-suspenders alongside
      # the wrapper's own poll loop. Timeout after 5 s to avoid
      # infinite hang if Hyprland fails to start.
      ExecStartPre = lib.mkForce "${pkgs.bash}/bin/bash -c 'i=0; while ! ${pkgs.hyprland}/bin/hyprctl instances -j 2>/dev/null | ${pkgs.jq}/bin/jq -e \".[0].instance\" >/dev/null 2>&1 && [ $i -lt 50 ]; do sleep 0.1; i=$((i+1)); done'";
    };
    # Auto-start only when the active theme uses waybar as its bar.
    # When theme.bar == "quickshell", waybar is not WantedBy any target
    # and won't auto-start. Conflicts= ensures that if waybar is
    # started manually, quickshell stops (and vice versa).
    Install = lib.optionalAttrs ((theme.bar or "waybar") == "waybar") {
      WantedBy = ["graphical-session.target"];
    };
  };

  # Restart waybar after HM activation when hyprland.conf changes.
  # HM reloads hyprland.conf via hyprctl reload, which desyncs
  # waybar's IPC state from the compositor — workspace indicators
  # freeze. Waybar's IPC thread has no retry: if the socket isn't
  # ready when waybar connects, IPC silently fails and the module
  # is permanently deaf. Cf. lesson 0005 Trigger B.
  #
  # This hook uses a 4-phase readiness probe instead of a fixed
  # sleep:
  #   1. Wait for Hyprland to finish reload (hyprctl responds).
  #   2. Restart waybar.
  #   3. Verify "Hyprland IPC starting" appears in waybar logs
  #      within 10 s — this line is the definitive diagnostic:
  #      present = IPC connected, absent = IPC silently failed.
  #   4. If IPC didn't start, Hyprland was still mid-reload.
  #      Wait 3 s, restart waybar once more, check again.
  #
  # Source: research 2026-06-26-waybar-ipc-freeze-deep-research
  # Solution 2 — deterministic post-rebuild restart with IPC
  # readiness probe.
  home.activation.restart-waybar-on-hyprland-change = lib.hm.dag.entryAfter ["writeBoundary"] ''
    if ${pkgs.systemd}/bin/systemctl --user is-active --quiet waybar.service 2>/dev/null; then
      # Phase 1: wait for Hyprland to finish reload.
      for _ in $(${pkgs.coreutils}/bin/seq 1 20); do
        if ${pkgs.hyprland}/bin/hyprctl instances -j 2>/dev/null | ${pkgs.jq}/bin/jq -e '.[0].instance' >/dev/null 2>&1; then
          break
        fi
        ${pkgs.coreutils}/bin/sleep 0.2
      done

      # Phase 2: restart waybar.
      ${pkgs.systemd}/bin/systemctl --user restart waybar.service 2>/dev/null || true

      # Phase 3: verify IPC started (poll logs for 10 s).
      ${pkgs.coreutils}/bin/sleep 1
      ipc_ok=false
      for _ in $(${pkgs.coreutils}/bin/seq 1 18); do
        if ${pkgs.systemd}/bin/journalctl --user -u waybar.service --since "30 sec ago" --no-pager 2>/dev/null | ${pkgs.gnugrep}/bin/grep -q "Hyprland IPC starting"; then
          ipc_ok=true
          break
        fi
        ${pkgs.coreutils}/bin/sleep 0.5
      done

      # Phase 4: retry once if IPC didn't start.
      if [ "$ipc_ok" = false ]; then
        ${pkgs.coreutils}/bin/sleep 3
        ${pkgs.systemd}/bin/systemctl --user restart waybar.service 2>/dev/null || true
        ${pkgs.coreutils}/bin/sleep 2
        ${pkgs.systemd}/bin/journalctl --user -u waybar.service --since "10 sec ago" --no-pager 2>/dev/null | ${pkgs.gnugrep}/bin/grep -q "Hyprland IPC starting" || true
      fi
    fi
  '';

  programs.waybar.settings.mainBar = {
    "hyprland/workspaces" =
      {
        on-click = "activate";
        cursor = true;
      }
      // (theme.waybar.workspaces or {
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
      });

    "hyprland/window" = {
      icon = false;
      format = "{title}";
      rewrite = {
        "(.*) — Mozilla Firefox" = "$1";
      };
      max-width = 100;
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
      # surrounding tray icons.
      #
      # exec: throne-status checks the throne-tun interface first
      # (class "vpn-active" → bright_green glow when TUN is up),
      # then falls back to the app-status cache for the "running"
      # class (window open but TUN down). Interval=3 polls the TUN
      # state — interface up/down doesn't emit Hyprland events.
      # Signal=8 gives instant updates when the Throne window
      # opens/closes (app-status-daemon sends SIGRTMIN+8).
      format = "<span weight='heavy'>󰦝</span>";
      exec = "${throne-status}/bin/throne-status";
      return-type = "json";
      interval = 3;
      signal = 8;
      on-click = "${throne-toggle}/bin/throne-toggle";
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

    # Hyprland-aware override of the universal `custom/volume`
    # slot: attach a hide/show on-click that toggles pwvucontrol via
    # Hyprland special-workspace IPC. Mute (on-click in the universal
    # config) is moved to on-click-right here.
    "custom/volume" = {
      on-click = lib.mkForce "${pwvucontrol-toggle}/bin/pwvucontrol-toggle";
      on-click-right = lib.mkForce "pamixer -t";
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
