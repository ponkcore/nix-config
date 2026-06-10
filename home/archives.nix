# archives.nix — archive management (GUI + CLI).
#
# kdePackages.ark — KDE file archiver. Drag-and-drop GUI,
#   integrates with Dolphin (not installed, but the .desktop
#   entry is visible in rofi). Supports zip, tar, 7z, rar,
#   and more via the backend packages listed below.
#
# CLI backends — ark calls these under the hood, and they
# are useful standalone in the terminal:
#   unzip / zip       — .zip
#   p7zip             — .7z (7za command)
#   unrar             — .rar (view-only; unrar is freeware, rar is paid)
#   gnutar            — .tar / .tar.gz / .tar.xz / .tar.zst
#   libarchive        — bsdtar (handles tar, zip, cpio, iso, and more)
#
# Why not file-roller (GNOME): Ark is lighter on GTK dependencies
# (we run a Qt/Kvantum theme stack) and has identical format support
# when the same backends are installed. Why not engrampa (MATE):
# same reason, plus less active maintenance.
{pkgs, ...}: {
  home.packages = [
    pkgs.kdePackages.ark

    # CLI backends — both ark and terminal use these
    pkgs.unzip
    pkgs.zip
    pkgs.p7zip
    pkgs.unrar
    pkgs.gnutar
    pkgs.libarchive
  ];
}
