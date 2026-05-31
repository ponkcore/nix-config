# imaging.nix — bootable USB / disk image creation tools.
#
# impression — GTK4/libadwaita GUI for flashing Linux ISOs (dd-style).
#   Drag-and-drop an ISO, pick the target USB drive, hit Start.
#   Best for one-shot Linux installer flashes.
#
# woeusb — purpose-built CLI/GUI for Windows ISOs. Handles
#   install.wim >4 GiB (FAT32 split or NTFS) and the UEFI:NTFS
#   bootloader bits that plain `dd` cannot. The `woeusbgui` binary
#   is a Python+wxWidgets frontend over the same engine.
#
# Why not Ventoy: nixpkgs marks ventoy insecure (opaque binary
# blobs in the ISO injector, no upstream audit trail —
# https://github.com/NixOS/nixpkgs/issues/404663). impression
# covers Linux, woeusb covers Windows — the gap closes without
# permitting an insecure package.
{pkgs, ...}: {
  home.packages = [
    pkgs.impression
    pkgs.woeusb
  ];
}
