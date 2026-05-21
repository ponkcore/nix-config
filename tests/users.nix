# tests/users.nix — verifies the primary-user contract.
#
# Boots a minimal NixOS VM that imports modules/nixos/users.nix and
# modules/nixos/security.nix, then asserts at runtime:
#   - the `oonishi` account exists,
#   - login shell is fish,
#   - sudo lets the user run `sudo -n true` without a password,
#   - the canonical group memberships are present.
#
# This is an end-to-end behavioural test, not a static one: it boots
# the kernel, reads /etc/passwd via getent, and shells out to sudo.
# Failures here are real regressions in the user/security modules.
{pkgs}:
pkgs.testers.runNixOSTest {
  name = "talos-users";

  nodes.machine = {lib, ...}: {
    imports = [
      ../modules/nixos/users.nix
      ../modules/nixos/security.nix
    ];
    # `username` is normally injected by lib/mkHost.nix specialArgs;
    # provide it explicitly here.
    _module.args.username = "oonishi";

    # Headless test environment: switch off services the security
    # module pulls in unconditionally and which would either need a
    # network or just slow the VM down with no test value. mkForce
    # is required because security.nix sets these to plain `true`,
    # which collides with a plain `false` here.
    services.openssh.enable = lib.mkForce false;
    services.fail2ban.enable = lib.mkForce false;
    networking.firewall.enable = lib.mkForce false;
  };

  testScript = ''
    machine.wait_for_unit("multi-user.target")

    # Account exists.
    machine.succeed("id oonishi")

    # Login shell is fish (resolves to the canonical /run/current-system path).
    machine.succeed(
        "getent passwd oonishi | awk -F: '{print $7}' | grep -E '/(bin|run/current-system/sw/bin)/fish$'"
    )

    # Sudo NOPASSWD: -n flag fails if a password would be needed.
    machine.succeed("sudo -u oonishi sudo -n true")

    # Universal groups — present whenever modules/nixos/users.nix is
    # imported, regardless of which other modules are loaded. Optional
    # service groups (networkmanager, libvirtd, docker) only exist
    # when their respective modules are imported, so verifying those
    # belongs in an integration test that pulls in the full host
    # closure rather than this isolated unit-style test.
    for group in ("wheel", "audio", "video", "render"):
        machine.succeed(f"id -nG oonishi | tr ' ' '\\n' | grep -qx {group}")
  '';
}
