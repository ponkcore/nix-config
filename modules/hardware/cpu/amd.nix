# cpu/amd.nix — AMD CPU enablement profile.
#
# Opt-in for any host running on an AMD CPU. Provides:
#   - microcode updates
#   - amd_pstate=active for fine-grained EPP control
#   - amd_iommu / iommu=pt for KVM passthrough overhead reduction
#   - kvm-amd kernel module (so libvirt can spawn HVM guests)
#
# auto-cpufreq tuning (governor, EPP, turbo) lives in
# modules/hardware/form-factor/laptop.nix because the policy
# (powersave on battery / performance on AC) is laptop-specific.
# Desktops and servers want different profiles.
_: {
  hardware.cpu.amd.updateMicrocode = true;

  boot = {
    kernelModules = ["kvm-amd"];
    kernelParams = [
      # AMD P-State: active mode for fine-grained EPP control (more efficient than passive).
      "amd_pstate=active"
      # AMD IOMMU enabled for KVM, with pass-through to reduce overhead for VM passthrough.
      "amd_iommu=on"
      "iommu=pt"
    ];
  };
}
