# wlogout.nix — graphical session-action menu.
#
# Opened from the Waybar power button. The four-button grid is adapted
# from the local HyDE-style reference, but actions stay native to this
# Hyprland session and icon assets are pinned through the Nix store.
{
  pkgs,
  p,
  ...
}: let
  icons = ../assets/wlogout-icons;
in {
  home.packages = [pkgs.wlogout];

  xdg.configFile."wlogout/layout".text = ''
    {
      "label"    : "lock",
      "action"   : "hyprlock",
      "text"     : "Lock",
      "keybind"  : "l"
    }
    {
      "label"    : "logout",
      "action"   : "hyprctl dispatch exit",
      "text"     : "Logout",
      "keybind"  : "e"
    }
    {
      "label"    : "shutdown",
      "action"   : "systemctl poweroff",
      "text"     : "Shutdown",
      "keybind"  : "s"
    }
    {
      "label"    : "reboot",
      "action"   : "systemctl reboot",
      "text"     : "Reboot",
      "keybind"  : "r"
    }
  '';

  xdg.configFile."wlogout/style.css".text = ''
    * {
      background-image: none;
      font-family: 'CaskaydiaCove Nerd Font Propo';
      font-size: 20px;
    }

    window {
      background-color: transparent;
    }

    button {
      color: ${p.fg};
      background-color: ${p.bg};
      outline-style: none;
      border: none;
      border-width: 0;
      background-repeat: no-repeat;
      background-position: center;
      background-size: 10%;
      border-radius: 0;
      box-shadow: none;
      text-shadow: none;
      transition: background-color 0.15s ease, color 0.15s ease, background-size 0.2s ease;
    }

    button:focus {
      color: ${p.hover_fg};
      background-color: ${p.accent_warm};
      background-size: 18%;
      box-shadow: none;
      outline-style: none;
    }

    button:hover {
      color: ${p.hover_fg};
      background-color: ${p.hover_bg};
      background-size: 18%;
    }

    #lock {
      background-image: image(url("${icons}/lock.png"));
      border-radius: 20px 0 0 0;
      margin: 8px 0 0 8px;
    }

    #logout {
      background-image: image(url("${icons}/logout.png"));
      border-radius: 0 0 0 20px;
      margin: 0 0 8px 8px;
    }

    #shutdown {
      background-image: image(url("${icons}/shutdown.png"));
      border-radius: 0 20px 0 0;
      margin: 8px 8px 0 0;
    }

    #reboot {
      background-image: image(url("${icons}/reboot.png"));
      border-radius: 0 0 20px 0;
      margin: 0 8px 8px 0;
    }
  '';
}
