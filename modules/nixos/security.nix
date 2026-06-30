# security.nix — SSH, firewall, sudo, PAM, sysctl hardening.
#
# Highlights:
#   - SSH password auth ENABLED by user choice.
#   - Firewall: only TCP 22 inbound, ICMP blocked, mihomo TUN trusted.
#   - sudo NOPASSWD for the primary user.
#   - PAM nullok forced off everywhere.
#   - Sysctl hardening pass — kexec lockout, redirects refused,
#     rp_filter strict, log_martians, tcp_rfc1337, etc.
{lib, ...}: {
  # SSH
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = true;
      PermitRootLogin = "no";
      KbdInteractiveAuthentication = true;
    };
  };

  # ── fail2ban ────────────────────────────────────────────────────────
  # The flake intentionally keeps SSH password authentication enabled
  # (see decisions/0002). That choice raises the brute-force surface,
  # so an automatic ban layer is the bare minimum due diligence.
  #
  # The default jail.local that NixOS ships only enables the sshd jail
  # when services.openssh is on, which is exactly what we want here.
  # ignoreIP keeps us from locking ourselves out via the local network
  # or the tailnet (CGNAT range used by Tailscale).
  services.fail2ban = {
    enable = true;
    # Tail journald rather than legacy /var/log files (NixOS uses
    # systemd-journald exclusively, plus this avoids polling text files).
    banaction = "iptables-multiport";
    bantime = "1h";
    bantime-increment = {
      enable = true;
      multipliers = "2 4 8 16 32 64";
      maxtime = "168h"; # 1 week ceiling
      overalljails = true;
    };
    ignoreIP = [
      "127.0.0.0/8"
      "::1"
      "10.0.0.0/8"
      "172.16.0.0/12"
      "192.168.0.0/16"
      "100.64.0.0/10" # Tailscale CGNAT
    ];
    jails.sshd.settings = {
      enabled = true;
      filter = "sshd";
      maxretry = 5;
      findtime = "10m";
      backend = "systemd";
    };
  };

  # Firewall
  networking.firewall = {
    allowedTCPPorts = [22];
    allowedUDPPorts = [];
    rejectPackets = true;
    allowPing = false;
    # Trust Throne's TUN interface — sing-box creates throne-tun for
    # transparent proxying. Without this, nixos-fw-log-refuse rejects
    # return traffic from TUN, breaking all connectivity when TUN mode
    # is active.
    trustedInterfaces = ["throne-tun"];
    # Log packets that would be refused but rate-limit to keep journal sane.
    # Useful for forensic review after a public-network session; the
    # 5/min rate cap prevents log-flood DoS.
    logRefusedPackets = true;
    logRefusedUnicastsOnly = true;
    logRefusedConnections = false;
  };

  # Sudo — passwordless for oonishi.
  # SECURITY NOTE: NOPASSWD is a deliberate trade-off for a personal
  # laptop. Threat model: network attack (mitigated by sysctl
  # hardening + fail2ban + firewall). Any process running as the
  # primary user can exec root commands — acceptable because the
  # alternative (password prompt on every sudo) disrupts the
  # declarative workflow (nixos-rebuild, agenix, systemctl).
  # NOT appropriate for shared or corporate systems.
  security.sudo = {
    enable = true;
    execWheelOnly = true;
    extraRules = [
      {
        users = ["oonishi"];
        commands = [
          {
            command = "ALL";
            options = ["NOPASSWD"];
          }
        ];
      }
    ];
  };

  # ── Kernel image integrity ─────────────────────────────────────────────
  # protectKernelImage: forbids loading kernel modules and writing to MSRs
  # at runtime, prevents kexec_load (already covered by sysctl below as
  # defense-in-depth), and locks down /dev/mem. Equivalent to setting
  # `kernel.lockdown = "integrity"` on Secure Boot systems; on this
  # non-Secure-Boot host it still raises the bar against post-exploit
  # rootkit installation. Module list is finalized at boot — declarative
  # NixOS rebuilds do not require runtime modprobe.
  security.protectKernelImage = true;

  # ── ptrace scope ──────────────────────────────────────────────────────
  # ptrace_scope = 2: only processes with CAP_SYS_PTRACE may attach. This
  # blocks gdb/strace from attaching to arbitrary user processes and shuts
  # down a class of credential-theft attacks (browser memory scraping,
  # SSH-agent dumping). Run debuggers with `sudo` when explicitly needed.
  boot.kernel.sysctl."kernel.yama.ptrace_scope" = 2;

  # Disable nullok — prevent empty-password login via greeter/su/sudo
  # NixOS sets allowNullPassword=true by default for login/greetd/su/sudo — override with mkForce
  security.pam.services.login.allowNullPassword = lib.mkForce false;
  security.pam.services.greetd.allowNullPassword = lib.mkForce false;
  security.pam.services.su.allowNullPassword = lib.mkForce false;
  security.pam.services.sudo.allowNullPassword = lib.mkForce false;
  security.pam.services.hyprlock = {};

  # Kernel sysctl
  boot.kernel.sysctl = {
    # Enable IP forwarding — required for TUN-based transparent proxy.
    # Without this, packets entering Meta interface cannot be forwarded
    # to the real interface (wlp12s0) and vice versa.
    "net.ipv4.ip_forward" = 1;

    # ── Hardening: kernel info leaks ─────────────────────────────────────
    "kernel.dmesg_restrict" = 1;
    "kernel.kptr_restrict" = 2;
    "kernel.unprivileged_bpf_disabled" = 1;
    "kernel.perf_event_paranoid" = 3;
    # Unprivileged user namespaces: kernel.unprivileged_userns_clone
    # is a Debian-specific patch, not in mainline kernel 6.18. The
    # mainline equivalent is user.max_user_namespaces=0, but that
    # blocks ALL user namespace creation including root — breaks Nix
    # build sandboxing. Leaving user namespaces enabled; mitigated
    # by ptrace_scope=2, protectKernelImage, and seccomp filters in
    # Docker/Nix builds.
    # dev.tty.ldisc_autodetect was removed in kernel 5.14+ — no
    # mainline equivalent exists.
    # NMI watchdog off — saves ~1% battery; this is the per-CPU lockup
    # detector that polls each core. The generic soft-lockup watchdog
    # (kernel.watchdog) MUST stay enabled — it's the diagnostic channel
    # for kernel deadlocks. Disabling it hides real bugs.
    "kernel.nmi_watchdog" = 0;
    # Soft-lockup watchdog ON. Previous config had this disabled, which
    # silenced legitimate deadlock diagnostics. Set explicitly to override
    # any leftover runtime value from older generations.
    "kernel.watchdog" = 1;
    # Block kexec_load: stop a privileged process (post-CAP_SYS_BOOT) from
    # booting an unsigned kernel. Defence-in-depth on a secure-boot-less laptop.
    "kernel.kexec_load_disabled" = 1;

    # ── Hardening: network — host posture (not a router) ─────────────────
    # Don't act as a router for ICMP redirects.
    "net.ipv4.conf.all.send_redirects" = 0;
    "net.ipv4.conf.default.send_redirects" = 0;
    # Refuse ICMP redirects we receive — modern networks don't legitimately use them.
    "net.ipv4.conf.all.accept_redirects" = 0;
    "net.ipv4.conf.default.accept_redirects" = 0;
    "net.ipv4.conf.all.secure_redirects" = 0;
    "net.ipv4.conf.default.secure_redirects" = 0;
    "net.ipv6.conf.all.accept_redirects" = 0;
    "net.ipv6.conf.default.accept_redirects" = 0;
    # No source routing.
    "net.ipv4.conf.all.accept_source_route" = 0;
    "net.ipv4.conf.default.accept_source_route" = 0;
    "net.ipv6.conf.all.accept_source_route" = 0;
    "net.ipv6.conf.default.accept_source_route" = 0;
    # Reverse-path filter on (strict) — drop spoofed packets at ingress.
    "net.ipv4.conf.all.rp_filter" = 1;
    "net.ipv4.conf.default.rp_filter" = 1;
    # Tailscale uses asymmetric routing by design — packets arrive on
    # tailscale0 with source addresses that don't match the expected
    # route. Strict rp_filter=1 drops them silently. Loose mode (2)
    # on the interface only, without weakening the global strict filter.
    # No-op when tailscale0 doesn't exist (manual start); applies on
    # next boot after Tailscale has been started at least once.
    "net.ipv4.conf.tailscale0.rp_filter" = 2;
    # Log packets with impossible source addresses (martians) for forensics.
    "net.ipv4.conf.all.log_martians" = 1;
    "net.ipv4.conf.default.log_martians" = 1;
    # Ignore broadcast pings (smurf attack mitigation).
    "net.ipv4.icmp_echo_ignore_broadcasts" = 1;
    # Ignore bogus ICMP error responses (already default, fixate).
    "net.ipv4.icmp_ignore_bogus_error_responses" = 1;
    # SYN flood protection.
    "net.ipv4.tcp_syncookies" = 1;
    # TCP RFC1337 — drop TIME_WAIT RST attacks.
    "net.ipv4.tcp_rfc1337" = 1;

    # ── IPv6 privacy extensions ─────────────────────────────────────────
    # NixOS already sets `use_tempaddr=2` on all/default via
    # nixos/modules/tasks/network-interfaces.nix — no need to redefine here.
    # The `regeneration time exceeded` warning seen in the kernel log is
    # benign: it fires when the host stays on one network long enough for
    # the temporary address lifetime to elapse. Linux disables tempaddr
    # generation on that interface but keeps the existing addresses; a
    # network change re-enables generation.
  };
}
