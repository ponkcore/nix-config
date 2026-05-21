# storage.nix — removable media + filesystem support.
#
# udisks2 + gvfs auto-mount USB sticks, SD cards, external drives at
# /run/media/<user>/<label>. Polkit rule lets `wheel` users mount
# without a password prompt. ntfs3 (kernel) blacklisted in favour of
# ntfs-3g (FUSE) which can mount Windows volumes that didn't run
# `chkdsk /f` cleanly.
{lib, ...}: {
  # udisks2 — D-Bus storage manager (mount/unmount/eject).
  services.udisks2.enable = true;

  # GVFS — GNOME virtual-FS layer. Without it Nautilus does not trigger
  # auto-mount on insertion and does not draw sidebar entries.
  services.gvfs.enable = true;

  # Mask unused GVFS volume monitors — saves ~15M RAM + D-Bus clutter.
  # gvfs-afc: Apple devices (iPhone/iPad) — not used
  # gvfs-goa: GNOME Online Accounts (Google Drive, etc.) — not configured
  # gvfs-gphoto2: digital cameras via PTP — not used
  # Kept: gvfs-daemon, gvfs-udisks2 (USB), gvfs-mtp (phones), gvfs-metadata
  systemd.user.services = {
    gvfs-afc-volume-monitor.enable = lib.mkForce false;
    gvfs-goa-volume-monitor.enable = lib.mkForce false;
    gvfs-gphoto2-volume-monitor.enable = lib.mkForce false;
  };

  # Kernel-level support for common removable filesystems.
  #   exfat  — USB sticks and SD cards formatted by Windows / cameras
  #   ntfs   — pulls ntfs-3g (FUSE) into systemPackages + mount.ntfs
  # ext4 / vfat are already supported by the base kernel.
  boot.supportedFilesystems = ["ntfs" "exfat"];

  # ntfs3 (kernel) cannot mount NTFS volumes that left Windows without a
  # clean `chkdsk /f` — fails with "wrong fs type". Block it: mount falls
  # through to ntfs-3g (FUSE) which can force-mount and run ntfsfix.
  boot.blacklistedKernelModules = ["ntfs3"];

  # Polkit rule: allow members of group `wheel` to mount / unmount /
  # eject removable media WITHOUT a password. udisks2 by default prompts
  # via polkit-agent — annoying on a personal laptop.
  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if (subject.isInGroup("wheel") && subject.local && subject.active) {
        if (action.id == "org.freedesktop.udisks2.filesystem-mount"
         || action.id == "org.freedesktop.udisks2.filesystem-mount-system"
         || action.id == "org.freedesktop.udisks2.filesystem-unmount-others"
         || action.id == "org.freedesktop.udisks2.eject-media"
         || action.id == "org.freedesktop.udisks2.power-off-drive") {
          return polkit.Result.YES;
        }
      }
    });
  '';
}
