# maintenance.nix — periodic disk hygiene.
#
# Universal: TRIM is supported by every modern SSD/NVMe. Monthly cadence
# avoids the multi-minute mid-day I/O stalls that weekly TRIM produced
# on the 1TB DRAM-less NVMe in the lecoo host. With ext4 + commit=60 +
# low disk usage, monthly is functionally equivalent for wear levelling.
#
# Hosts on rotational disks or with extreme write workloads can override
# `services.fstrim.interval` per-host.
_: {
  services.fstrim = {
    enable = true;
    interval = "monthly";
  };

  # nano is default-enabled by NixOS — replaced everywhere by neovim
  # (see home/neovim.nix). Universal hygiene.
  programs.nano.enable = false;
}
