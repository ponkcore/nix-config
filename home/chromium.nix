# chromium.nix — Chromium browser.
# Primarily for web apps that require Chromium-specific APIs
# (e.g. File System Access API / showDirectoryPicker) which
# Firefox does not implement.
{pkgs, ...}: {
  home.packages = [
    pkgs.chromium
  ];
}
