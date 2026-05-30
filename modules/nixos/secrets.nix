# secrets.nix — agenix wiring + secret declarations.
#
# Declares which encrypted files in ../../secrets/ are decrypted at
# system activation, where they land, and who owns them. The agenix
# NixOS module reads `/etc/ssh/ssh_host_ed25519_key` automatically.
#
# Adding a new secret:
#   1. Encrypt: cd secrets && agenix -e <name>.age   (interactive)
#   2. List its public keys in secrets/secrets.nix.
#   3. Add an `age.secrets.<name>` block here.
#   4. Reference `config.age.secrets.<name>.path` from the consumer.
{
  inputs,
  pkgs,
  username,
  ...
}: {
  imports = [inputs.agenix.nixosModules.default];

  age = {
    # Identity used to decrypt at activation time. Default works on every
    # host that has openssh enabled (which we always do — see services.nix).
    identityPaths = ["/etc/ssh/ssh_host_ed25519_key"];

    # tokens.age — bundle of all third-party API tokens consumed by
    # user-space agent tooling (gptme runtime, opencode runtime,
    # opencode MCP clients). Decrypted to /run/agenix/tokens at
    # activation, owner = primary user, mode 400.
    secrets.tokens = {
      file = ../../secrets/tokens.age;
      owner = username;
      mode = "400";
    };
  };

  # agenix CLI available system-wide for `agenix -e` workflow.
  environment.systemPackages = [
    inputs.agenix.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];
}
