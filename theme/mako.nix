{p, ...}: {
  # mako — Wayland notification daemon.
  #
  # In Home Manager 25.11 the `services.mako` module installs the package
  # and registers the D-Bus service file, but does NOT create a systemd
  # user unit. mako is started on demand by dbus-broker the first time
  # something issues a notification on `org.freedesktop.Notifications`.
  #
  # This means `systemctl --user is-active mako` reports `inactive` after
  # boot until the first notify — that is correct, not a regression.
  # makoctl reload is wired via xdg.configFile onChange.
  services.mako = {
    enable = true;
    settings = {
      "text-color" = p.fg_dim;
      "border-color" = p.fg_bright;
      "background-color" = p.bg;
      width = 500;
      height = 110;
      padding = 10;
      "border-size" = 2;
      "border-radius" = 4;
      font = "Noto Sans 14";
      anchor = "top-right";
      "outer-margin" = 20;
      "default-timeout" = 5000;
      "max-icon-size" = 32;

      "mode=do-not-disturb" = {invisible = true;};
      "mode=do-not-disturb app-name=notify-send" = {invisible = false;};
    };
  };
}
