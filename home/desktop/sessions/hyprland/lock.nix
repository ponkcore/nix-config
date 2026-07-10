# lock.nix — Wayland lock screen (Hyprland session).
#
# hyprlock is DISABLED. Caelestia Lock (Phase 3E) owns the lock path.
# The hyprlock configuration below is retained for reference. If
# Caelestia Lock ever needs to be rolled back, re-enable this module
# deliberately and repin the shell to a known-good revision.
#
# Caelestia Lock uses its own PAM configs (assets/pam.d/) and
# WlSessionLock for Wayland session locking. Triggered via:
#   - SUPER+Escape bind (session.nix) → loginctl lock-session
#   - Caelestia IPC: caelestia shell lock lock/unlock
#   - loginctl lock/unlock-session (D-Bus → SessionManager)
{
  config,
  p,
  c,
  wallpaper,
  ...
}: let
  rgba = c.gtkRGBA;
in {
  # Accepted final state: hyprlock disabled. Caelestia Lock owns the lock
  # path; the retained config below is reference-only.
  programs.hyprlock = {
    enable = false;

    settings = {
      general = {
        hide_cursor = true;
        immediate_render = true;
      };

      background = [
        {
          monitor = "";
          path = wallpaper;
          blur_passes = 0;
          contrast = 0.8916;
          brightness = 0.8916;
          vibrancy = 0.8916;
          vibrancy_darkness = 0.0;
        }
      ];

      image = [
        {
          monitor = "";
          path = "${config.xdg.dataHome}/profile.jpg";
          border_size = 2;
          border_color = rgba p.bright_blue 0.71;
          size = 100;
          rounding = -1;
          rotate = 0;
          reload_time = -1;
          position = "0, 170";
          halign = "center";
          valign = "center";
        }
      ];

      label = [
        {
          monitor = "";
          text = "$USER";
          color = rgba p.fg_bright 0.80;
          font_size = 20;
          font_family = "CaskaydiaCove Nerd Font Propo";
          position = "0, 80";
          halign = "center";
          valign = "center";
        }
        {
          monitor = "";
          text = ''cmd[update:1000] echo "<span>$(date +"%I:%M")</span>"'';
          color = rgba p.fg_bright 0.80;
          font_size = 60;
          font_family = "CaskaydiaCove Nerd Font Propo";
          position = "0, -20";
          halign = "center";
          valign = "center";
        }
        {
          monitor = "";
          text = ''cmd[update:1000] echo -e "$(date +"%A, %B %d")"'';
          color = rgba p.fg_bright 0.80;
          font_size = 19;
          font_family = "CaskaydiaCove Nerd Font Propo Bold";
          position = "0, -90";
          halign = "center";
          valign = "center";
        }
        {
          monitor = "";
          text = "  $USER";
          color = rgba p.fg_bright 0.80;
          font_size = 16;
          font_family = "CaskaydiaCove Nerd Font Propo";
          position = "0, -190";
          halign = "center";
          valign = "center";
        }
      ];

      shape = [
        {
          monitor = "";
          size = "500, 500";
          color = rgba p.bg 0.62;
          rounding = 30;
          border_size = 0;
          border_color = rgba p.bright_magenta 0.5;
          rotate = 0;
          xray = false;
          position = "0, -70";
          halign = "center";
          valign = "center";
        }
        {
          monitor = "";
          size = "320, 55";
          color = "rgba(255, 255, 255, 0.1)";
          rounding = -1;
          border_size = 0;
          border_color = "rgba(255, 255, 255, 1.0)";
          rotate = 0;
          xray = false;
          position = "0, -190";
          halign = "center";
          valign = "center";
        }
      ];

      input-field = [
        {
          monitor = "";
          size = "320, 55";
          outline_thickness = 0;
          dots_size = 0.2;
          dots_spacing = 0.2;
          dots_center = true;
          outer_color = "rgba(255, 255, 255, 0)";
          inner_color = "rgba(255, 255, 255, 0.1)";
          font_color = rgba p.fg_dim 1.0;
          check_color = rgba p.bright_green 0.6;
          fail_color = rgba p.bright_red 0.6;
          fade_on_empty = false;
          placeholder_text = "<i><span foreground=\"#${p.fg_bright}99\">  Enter Pass</span></i>";
          hide_input = false;
          position = "0, -268";
          halign = "center";
          valign = "center";
        }
      ];
    };
  };
}
