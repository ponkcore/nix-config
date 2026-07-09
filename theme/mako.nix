{
  p,
  theme, # reserved for future per-theme structural overrides
  ...
}: {
  # mako is disabled. Caelestia shell owns org.freedesktop.Notifications
  # via its built-in notification service (Quickshell.Services.Notifications).
  # Notification rendering, DND, and history live in the shell.
  # DND helper scripts use `caelestia shell notifs` IPC (see scripts.nix).
  #
  # The old mako configuration is preserved below for reference.
  # If Caelestia notification ownership needs to be reverted, re-enable
  # this block and restart caelestia.service.
  services.mako = {
    enable = false;
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
