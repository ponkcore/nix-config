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
      font-family: 'DepartureMono Nerd Font Propo';
      font-size: 26px;
      font-weight: bold;
      border-radius: 10px;
    }

    window {
      background-color: rgba(0, 0, 0, 0);
    }

    button {
      color: ${p.bg};
      background-color: ${p.accent_warm};
      outline-style: none;
      border: none;
      box-shadow: none;
      background-repeat: no-repeat;
      background-position: center;
      background-size: 45%;
    }

    button:hover,
    button:focus {
      color: ${p.bg};
      background-color: ${p.bright_magenta};
      background-size: 90%;
    }

    #lock {
      background-image: image(url("${icons}/lock.png"));
    }

    #logout {
      background-image: image(url("${icons}/logout.png"));
    }

    #shutdown {
      background-image: image(url("${icons}/shutdown.png"));
    }

    #reboot {
      background-image: image(url("${icons}/reboot.png"));
    }

    #lock,
    #logout,
    #shutdown,
    #reboot {
      margin: 3px 0px;
    }
  '';
}
