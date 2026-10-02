# nix.nix — Nix daemon policy + memory/swap tuning.
#
# Centralised here so all nix-related config lives in one place:
# `allowUnfree`, flakes/nix-command, GC schedule, store optimise,
# zram, /tmp on tmpfs, vm.* sysctls, journald retention, coredump cap.
{lib, ...}: {
  # Explicit allow-list for unfree packages. Every unfree package must
  # be listed here by name — blanket allowUnfree=true is replaced with
  # a predicate so the set of unfree software is visible and auditable
  # in the configuration. Add new unfree packages here when adopted.
  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (lib.getName pkg) [
      "antigravity-cli"
      "claude-code"
      "obsidian"
      "oh-my-openagent"
      "spotify"
      "steam-unwrapped"
      "unrar"
    ];

  # Docker insecure flag removed — 26.05 ships Docker 29.5.3.

  # Flakes + nix-command
  nix.settings.experimental-features = ["nix-command" "flakes"];

  # Deduplication & optimisation
  # auto-optimise-store: hard-link identical files at insertion time.
  # This runs after every build and catches duplicates incrementally.
  # A separate nix.optimise.automatic batch job is redundant — it would
  # find nothing to do and cause a periodic I/O spike for no benefit.
  nix.settings.auto-optimise-store = true;

  # GC retention policy. Both keys default to true in Nix, and leaving
  # them there silently disabled garbage collection: the weekly nix-gc
  # freed 1.7 GiB out of an 85 GB store, because every build output
  # reachable from a retained .drv counted as live.
  #
  # keep-derivations = true — retain .drv metadata for live paths.
  # Costs ~0.26 GB and buys `nix log`, `nix derivation show` and rebuild
  # tracing for anything currently installed.
  #
  # keep-outputs = false — do NOT retain build outputs of dead
  # derivations. This is the flag that was pinning ~51 GB of stale
  # outputs (7056 paths, measured with du, hard-link aware).
  #
  # The previous comment here claimed keep-derivations protects
  # nix-direnv dev shells. That was wrong: nix-direnv registers its own
  # GC roots (`.direnv/flake-profile-*` symlinks under
  # /nix/var/nix/gcroots/auto/), which keep dev-shell closures live
  # regardless of these settings. Verified before the change: the
  # intersection of both live dev-shell closures with the GC dead set
  # was zero.
  nix.settings.keep-derivations = true;
  nix.settings.keep-outputs = false;

  # Automatic garbage collection.
  # 14d gives enough breathing room to roll back ~2 weeks of generations
  # while the weekly cadence keeps the disk lean. Previous 7d was overly
  # aggressive — we'd lose generation history of a long weekend off.
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
    persistent = true;
  };

  # Boot entries are written only by activation, but GC deletes profiles
  # on its own schedule — so between a GC run and the next rebuild the
  # loader keeps entries whose `init=` points at a deleted store path.
  # That happened with generation 635 (removed by GC on 2026-09-28, entry
  # survived until the next switch): selecting it at boot would have
  # failed to load.
  #
  # `switch-to-configuration boot` rewrites /boot/loader/entries from the
  # profiles that still exist. systemd-boot-builder.py's
  # remove_old_entries() unlinks any entry whose generation is not in the
  # live profile list. The `boot` action only installs the bootloader —
  # it does NOT activate, so it never restarts units or touches the
  # running system.
  #
  # Verified before enabling: merging ExecStartPost onto the nixpkgs unit
  # preserves ExecStart and nix.gc.options; the command is idempotent
  # (repeated runs leave entries byte-identical); and a decisive test —
  # dropping in a synthetic entry for nonexistent generation 999 with a
  # broken init path — was removed by one run, with all real entries
  # restored 1:1.
  #
  # Why not lower boot.loader.systemd-boot.configurationLimit instead:
  # that trims entries during activation too, so it narrows the window
  # but does not close it. At 9 rebuilds per 14 days against a limit of
  # 7 the window is live on this host.
  #
  # The path is the runtime /run/current-system, deliberately NOT
  # ${config.system.build.toplevel}: referencing toplevel from inside a
  # unit that is itself part of toplevel is self-referential and fails
  # evaluation with "infinite recursion encountered". Going through
  # /run/current-system is also the semantically right choice — the GC
  # runs against the active generation, and its switch-to-configuration
  # wrapper has that generation's bootloader settings (configurationLimit
  # and friends) baked in, which is exactly what the entries should
  # reflect.
  systemd.services.nix-gc.serviceConfig.ExecStartPost = [
    "/run/current-system/bin/switch-to-configuration boot"
  ];

  # zram-swap — 30% of physical RAM, zstd-compressed. Defaults to
  # priority 5; deliberately not overridden here so the kernel applies
  # its own swap-priority arithmetic without manual interference.
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 30;
  };

  # /tmp on tmpfs — RAM-backed, auto-cleaned on reboot.
  # 25 % cap (≈8 GB on a 30 GB host) is the trade-off between letting
  # build / dev workloads stay in RAM and not racing zramSwap for the
  # same pages under heavy multitasking. Larger one-shot consumers
  # (video transcoding, big tar extractions) should use /var/tmp on
  # disk anyway; the systemd-tmpfiles policy already routes long-lived
  # state there.
  boot.tmp.useTmpfs = true;
  boot.tmp.tmpfsSize = "25%";

  # Transparent Huge Pages are controlled by the kernel command line,
  # not sysctl. `transparent_hugepage=madvise` keeps THP opt-in for
  # workloads that request it without producing systemd-sysctl noise.
  boot.kernelParams = ["transparent_hugepage=madvise"];

  # VM / sysctl tunables for dev + LLM/agent workload
  boot.kernel.sysctl = {
    # swappiness=180: zram is compressed RAM, not disk swap — kernel should
    # eagerly move cold pages to zram to free real RAM for cache/hot pages
    # (Fedora uses 100, 180 is recommended for zram-optimized desktops)
    "vm.swappiness" = 180;
    "vm.vfs_cache_pressure" = 50;
    "vm.dirty_ratio" = 6;
    "vm.dirty_background_ratio" = 3;
    "fs.file-max" = 524288;
    "fs.inotify.max_user_watches" = 524288;
    "fs.inotify.max_user_instances" = 1024;
  };

  # Limit core dumps — 500MB total, delete after 3 days.
  # 26.05: systemd.coredump.extraConfig removed → structured settings.
  systemd.coredump.settings.Coredump = {
    MaxUse = "500M";
    MaxRetentionSec = "3d";
  };

  # Limit journal size — prevent unbounded growth.
  # 500M / 3 months: enough headroom to forensically investigate a problem
  # that surfaced two months ago without filling the disk.
  services.journald.extraConfig = ''
    SystemMaxUse=500M
    MaxRetentionSec=3month
    Compress=yes
    ForwardToSyslog=no
  '';
}
