# imaging.nix — bootable USB / disk image creation tools.
#
# impression — GTK4/libadwaita GUI for flashing Linux ISOs (dd-style).
#   Drag-and-drop an ISO, pick the target USB drive, hit Start.
#   Best for one-shot Linux installer flashes.
#
# woeusb-ng — purpose-built tool for Windows ISOs. Handles
#   install.wim >4 GiB (FAT32 split or NTFS) and the UEFI:NTFS
#   bootloader bits that plain `dd` cannot. Ships both the `woeusb`
#   CLI and the `woeusbgui` Python+wxWidgets frontend (with a
#   .desktop entry visible in rofi). The original `woeusb` package
#   in nixpkgs is CLI-only — we want the GUI flow too.
#
# Why not Ventoy: nixpkgs marks ventoy insecure (opaque binary
# blobs in the ISO injector, no upstream audit trail —
# https://github.com/NixOS/nixpkgs/issues/404663). impression
# covers Linux, woeusb covers Windows — the gap closes without
# permitting an insecure package.
{pkgs, ...}: {
  home.packages = [
    pkgs.impression
    pkgs.woeusb-ng
  ];
}
