# qt.nix — Qt theming via Kvantum + qt6ct.
# Kvantum needs the theme directory at runtime; gruvbox-kvantum
# installs share/Kvantum/Gruvbox-Dark-Brown/, but Nix buildEnv does
# not symlink it into the user profile, so we explicitly route it via
# xdg.dataFile.
{pkgs, ...}: {
  qt = {
    enable = true;
    # `qtct` is a Home Manager legacy alias that maps to
    # `QT_QPA_PLATFORMTHEME=qt5ct`. Qt 6 apps (e.g. Throne 1.0.13
    # built against qtbase 6.11) ignore that bridge and fall back
    # to default style. We set qt6ct explicitly; both `libqt5ct.so`
    # and `libqt6ct.so` plugins are installed via the qt5/qt6
    # profiles, and Qt 5 apps still pick up the qt5ct fallback
    # from PlatformTheme plugin discovery.
    platformTheme.name = "qt6ct";
    style.name = "kvantum";
  };

  home.packages = with pkgs; [
    gruvbox-kvantum
    qt6Packages.qt6ct
  ];

  # Kvantum must find the theme directory at runtime.
  # gruvbox-kvantum installs share/Kvantum/Gruvbox-Dark-Brown/ but
  # Nix buildEnv does NOT symlink it into the user profile.
  # Explicitly link it via xdg.dataFile so Kvantum discovers it.
  xdg.dataFile = let
    src = "${pkgs.gruvbox-kvantum}/share/Kvantum/Gruvbox-Dark-Brown";
  in {
    "Kvantum/Gruvbox-Dark-Brown".source = src;
  };

  xdg.configFile."Kvantum/kvantum.kvconfig".text = ''
    [General]
    theme=Gruvbox-Dark-Brown
  '';

  # qt6ct config — without it qt6ct loads as a platform theme but
  # picks the Fusion style by default, ignoring QT_STYLE_OVERRIDE
  # and effectively wiping out Kvantum. Setting `style=kvantum`
  # here delegates the look to Kvantum (which uses the
  # Gruvbox-Dark-Brown theme set above). Everything else is left
  # at qt6ct defaults — fonts and palette flow through Kvantum.
  xdg.configFile."qt6ct/qt6ct.conf".text = ''
    [Appearance]
    style=kvantum
    standard_dialogs=default
    custom_palette=false
  '';
}
