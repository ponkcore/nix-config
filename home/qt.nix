# qt.nix — Qt theming via Kvantum + qt6ct.
# Kvantum needs the theme directory at runtime; gruvbox-kvantum
# installs share/Kvantum/Gruvbox-Dark-Brown/, but Nix buildEnv does
# not symlink it into the user profile, so we explicitly route it via
# xdg.dataFile.
{pkgs, ...}: {
  qt = {
    enable = true;
    platformTheme.name = "qtct";
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
}
