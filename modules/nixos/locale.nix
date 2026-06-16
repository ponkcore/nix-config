# locale.nix — timezone, language, keyboard.
#
# Profile: English UI everywhere, with regional bits cherry-picked
# to match what an РФ user is used to (metric, A4, 24-hour clock,
# Monday-first weeks, dot/comma number separators) — but without
# leaking any Russian-language strings into menus, calendars, or
# tooltips. Currency is intentionally USD because the user prefers
# it, even though the rest of the regional choices lean European.
#
# Why these specific locales:
#   en_GB → 22/05/2026, 24-hour clock, Monday-first weeks, A4,
#           metric measurements (m, km, °C). Closest English
#           locale to РФ habits without RU-language fallout.
#   en_DK → 1.234,56 number separators (point for thousands,
#           comma for decimals) — matches Russian convention.
#           Used as a numeric workaround; Danish-English is the
#           standard hack for "I want metric + comma-decimals
#           but English UI".
#   en_US → USD, $-prefixed monetary formatting.
#
# Layout US+RU with Caps Lock as the toggle.
#
# Timezone is the only field a generic VM host might want to override —
# host modules can set `time.timeZone = lib.mkForce "..."` if needed.
_: {
  time.timeZone = "Europe/Moscow";

  i18n = {
    defaultLocale = "en_US.UTF-8";
    # `extraLocaleSettings` only sets the env vars — the actual
    # locale data has to be generated separately. NixOS defaults
    # to only the `defaultLocale`, so en_GB and en_DK won't exist
    # in `locale -a` unless we list them here.
    supportedLocales = [
      "en_US.UTF-8/UTF-8"
      "en_GB.UTF-8/UTF-8"
      "en_DK.UTF-8/UTF-8"
      "ru_RU.UTF-8/UTF-8"
    ];
    extraLocaleSettings = {
      LC_TIME = "en_GB.UTF-8";
      LC_PAPER = "en_GB.UTF-8";
      LC_MEASUREMENT = "en_GB.UTF-8";
      LC_NUMERIC = "en_DK.UTF-8";
      LC_MONETARY = "en_US.UTF-8";
    };
  };

  # Keyboard layout — also drives the TTY console keymap via useXkbConfig.
  console.useXkbConfig = true;
  services.xserver.xkb = {
    layout = "us,ru";
    options = "grp:caps_toggle";
  };

  # Logind: laptop hosts override HandleLidSwitch* via modules/hardware/
  # form-factor/laptop.nix. Short power-key presses are left to the
  # active compositor so Hyprland can open the graphical power menu;
  # long-press remains a system-level emergency poweroff fallback.
  services.logind.settings.Login = {
    HandlePowerKey = "ignore";
    HandlePowerKeyLongPress = "poweroff";
  };
}
