# lock.nix — Wayland lock screen (Hyprland session).
# Nine widgets: background image, fingerprint hint, four labels (clock,
# date, hostname, greeting), two decorative shapes, password input.
# Triggered manually (SUPER+L is bound elsewhere) or via hypridle
# timeout from ./idle.nix.
{
  config,
  pkgs,
  p,
  c,
  wallpaper,
  ...
}: let
  rgba = c.gtkRGBA;
in {
  programs.hyprlock = {
    enable = true;

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
