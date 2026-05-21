# virtualisation.nix — libvirt + qemu_kvm.
#
# onBoot=ignore so no VMs auto-start on system boot. virt-manager
# included for GUI VM management. SuccessExitStatus workaround for
# libvirt 11.7.0's cosmetic exit-1 on idle socket-activation shutdown.
{pkgs, ...}: {
  virtualisation.libvirtd = {
    enable = true;
    onBoot = "ignore";
    onShutdown = "shutdown";
    qemu = {
      package = pkgs.qemu_kvm;
    };
  };

  programs.virt-manager.enable = true;

  # Disable libvirt-guests service — no VMs to save/restore, eliminates shutdown errors
  systemd.services.libvirt-guests.enable = false;

  # libvirt 11.7.0 socket-activated daemon (`--timeout 120`) exits with status
  # 1 after its idle "forceful daemon shutdown" path instead of 0, which
  # systemd reports as `failed`. The next client request via libvirtd.socket
  # transparently respawns the daemon, so the failure is purely cosmetic.
  # Tell systemd to treat 1 as a successful exit so the unit doesn't litter
  # `systemctl --failed` output.
  systemd.services.libvirtd.serviceConfig.SuccessExitStatus = ["0" "1"];
}
