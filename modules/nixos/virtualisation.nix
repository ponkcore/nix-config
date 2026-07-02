# virtualisation.nix — libvirt + qemu_kvm.
#
# onBoot=ignore so no VMs auto-start on system boot. virt-manager
# included for GUI VM management. SuccessExitStatus workaround for
# libvirt 11.7.0's cosmetic exit-1 on idle socket-activation shutdown.
#
# OVMF (UEFI firmware): since nixpkgs 26.05 the qemu.ovmf submodule is
# removed — OVMF images are bundled with QEMU and symlinked into
# /run/libvirt/nix-ovmf/ automatically. No config needed.
{pkgs, ...}: {
  virtualisation.libvirtd = {
    enable = true;
    onBoot = "ignore";
    onShutdown = "shutdown";
    qemu = {
      package = pkgs.qemu_kvm;
      # Virtual TPM 2.0 — required for Windows 11, useful for
      # guest secure boot / disk encryption with TPM pin.
      swtpm.enable = true;
      # virtio-fs daemon — paravirtual file sharing between host
      # and guest. Faster than 9p/Samba, no network layer overhead.
      vhostUserPackages = [pkgs.virtiofsd];
    };
  };

  # USB redirection via SPICE — allows passing physical USB devices
  # (flash drives, tokens, phones) from host to guest VM.
  virtualisation.spiceUSBRedirection.enable = true;

  programs.virt-manager.enable = true;

  environment.systemPackages = with pkgs; [
    virt-viewer # standalone SPICE client (better than embedded virt-manager console)
    spice-gtk # SPICE clipboard/display library
    swtpm # TPM emulator (also pulled by swtpm.enable, explicit for CLI access)
    virtiofsd # virtio-fs daemon (also pulled by vhostUserPackages, explicit for CLI access)
  ];

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
