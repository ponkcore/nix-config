# packages.nix — system-wide CLI tools.
#
# Per-user CLI replacements (bat, eza, fzf, zoxide, delta) live in
# home/cli.nix because they're shell-bound. This file keeps anything
# that should be on $PATH for any user (root included) on any host.
#
# Language toolchains (node, python, go, rust, bun, uv) are intentionally
# NOT installed system-wide. Each project gets its own pinned toolchain
# via a local flake / shell.nix loaded by direnv (already configured in
# home/direnv.nix). System-wide installs leak ~2 GB of closures into
# every host and force lock-step upgrades across unrelated projects.
{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    # ── Basics ──
    curl
    wget
    jq

    # ── Build essentials (kept system-wide for sudo nixos-rebuild and
    #    occasional ad-hoc compilation; language toolchains live in
    #    per-project devShells via direnv) ──
    gcc
    gnumake

    # ── Modern CLI replacements (system-level only; bat/eza/fzf/zoxide/delta live in HM) ──
    ripgrep
    fd
    tmux
    dua

    # ── System utilities ──
    pciutils
    usbutils
    lm_sensors
    smartmontools
    nix-output-monitor
    nh

    # ── Power diagnostics ──
    # turbostat must match the running kernel version — use
    # linuxPackages_latest.turbostat (currently 7.1.1). Reports
    # per-package/core C-states, frequency, and RAPL power.
    # powertop: total power estimates, wakeups, device power states,
    # tunables. Supports --auto-tune.
    # msr module is required for turbostat MSR reads — added in
    # boot.kernelModules via laptop.nix.
    # libva-utils: vainfo — verifies VA-API hardware decode support
    # on radeonsi (needed to confirm Firefox VA-API config).
    # nvme-cli: NVMe SMART, APST feature check, firmware info.
    powertop
    pkgs.linuxPackages_latest.turbostat
    libva-utils
    nvme-cli

    # ── Nix code quality (used by .pre-commit-config.yaml) ──
    pre-commit
    alejandra
    statix
    deadnix
    # nil — Nix language server. Single-file diagnostics in
    # pre-commit (`nil diagnostics <file>`) catch evaluation-time
    # errors that surface lints (alejandra/statix/deadnix) miss.
    # The LSP daemon is not enabled here; Neovim users have it
    # via home/neovim.nix. Editor-side diagnostics are still the
    # first line of defence — pre-commit is the safety net.
    nil
    # gitleaks — secret scanner. Used by .pre-commit-config.yaml as
    # a local mirror of the CI gitleaks job (.github/workflows/
    # check.yml:secrets-scan). SOUL §7 + ABOUT.md list it as a
    # mandatory commit-time gate; without the local hook a leak
    # would only be caught after `git push`. Offline binary, no
    # licence, scans the full history.
    gitleaks

    pamixer
    wireplumber
    playerctl

    # ── Archive ──
    unzip
    zip
    p7zip

    # ── File manager ──
    nautilus
  ];
}
