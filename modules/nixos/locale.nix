# locale.nix — timezone, language, keyboard.
#
# This particular profile (en_US base + ru_RU regional) reflects the
# user's preference: English UI everywhere, Russian formats for dates,
# numbers, currency. Layout US+RU with Caps Lock as the toggle.
#
# Timezone is the only field a generic VM host might want to override —
# host modules can set `time.timeZone = lib.mkForce "..."` if needed.
_: {
  time.timeZone = "Europe/Moscow";

  i18n = {
    defaultLocale = "en_US.UTF-8";
    extraLocaleSettings = {
      LC_ADDRESS = "ru_RU.UTF-8";
      LC_IDENTIFICATION = "ru_RU.UTF-8";
      LC_MEASUREMENT = "ru_RU.UTF-8";
      LC_MONETARY = "ru_RU.UTF-8";
      LC_NAME = "ru_RU.UTF-8";
      LC_NUMERIC = "ru_RU.UTF-8";
      LC_PAPER = "ru_RU.UTF-8";
      LC_TELEPHONE = "ru_RU.UTF-8";
      LC_TIME = "ru_RU.UTF-8";
    };
  };

  # Keyboard layout — also drives the TTY console keymap via useXkbConfig.
  console.useXkbConfig = true;
  services.xserver.xkb = {
    layout = "us,ru";
    options = "grp:caps_toggle";
  };

  # Logind: laptop hosts override HandleLidSwitch* via modules/hardware/
  # form-factor/laptop.nix. The power key behaviour is universal.
  services.logind.settings.Login = {
    HandlePowerKey = "poweroff";
    HandlePowerKeyLongPress = "poweroff";
  };
}
