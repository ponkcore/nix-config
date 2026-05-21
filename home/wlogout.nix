# wlogout.nix — graphical session-action menu (lock/logout/suspend/reboot/poweroff).
# Triggered manually; no keybind by default. Palette via _module.args.p.
{
  pkgs,
  p,
  ...
}: {
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
      "label"    : "suspend",
      "action"   : "systemctl suspend",
      "text"     : "Suspend",
      "keybind"  : "s"
    }
    {
      "label"    : "reboot",
      "action"   : "systemctl reboot",
      "text"     : "Reboot",
      "keybind"  : "r"
    }
    {
      "label"    : "shutdown",
      "action"   : "systemctl poweroff",
      "text"     : "Shutdown",
      "keybind"  : "p"
    }
  '';
  xdg.configFile."wlogout/style.css".text = ''
    * {
      font-family: 'CaskaydiaCove Nerd Font Propo';
      font-size: 20px;
    }
    window {
      background-color: ${p.bg};
    }
    button {
      background-color: ${p.bg_mid};
      color: ${p.fg};
      border: 2px solid ${p.border_inact};
      border-radius: 8px;
      margin: 12px;
      padding: 20px;
      background-repeat: no-repeat;
      background-size: contain;
      background-position: center;
    }
    button:hover {
      background-color: ${p.hover_bg};
      color: ${p.hover_fg};
      border-color: ${p.accent_warm};
    }
    button:focus {
      border-color: ${p.accent_warm};
      box-shadow: 0 0 0 2px ${p.accent_warm};
    }
    #lock, #logout, #suspend, #reboot, #shutdown {
      color: ${p.fg};
      font-weight: bold;
    }
    #shutdown {
      color: ${p.bright_red};
      border-color: alpha(${p.red}, 0.4);
    }
    #shutdown:hover {
      background-color: alpha(${p.red}, 0.2);
      color: ${p.bright_red};
      border-color: ${p.bright_red};
    }
    #reboot {
      color: ${p.bright_yellow};
      border-color: alpha(${p.bright_yellow}, 0.3);
    }
    #suspend {
      color: ${p.bright_blue};
    }
  '';
}
