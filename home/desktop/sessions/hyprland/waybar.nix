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
  # Waybar must start with Hyprland's runtime environment, not just
  # after the user session target. On cold boot UWSM can import
  # HYPRLAND_INSTANCE_SIGNATURE into the systemd user manager after
  # waybar is already eligible to start; without the signature,
  # hyprland/workspaces skips IPC entirely. Cf. lesson 0005.
  systemd.user.services.waybar = {
    Unit = {
      After = ["graphical-session.target" "wayland-wm@Hyprland.service" "app-status-daemon.service"];
      Wants = ["app-status-daemon.service"];
    };
    Service.ExecStart = lib.mkForce "${waybar-with-hyprland-env}";
  };

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
