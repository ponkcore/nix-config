# secrets.nix — agenix wiring + secret declarations.
#
# Declares which encrypted files in ../../secrets/ are decrypted at
# system activation, where they land, and who owns them. The agenix
# NixOS module reads `/etc/ssh/ssh_host_ed25519_key` automatically.
#
# Adding a new secret:
#   1. Encrypt:
#        - interactive editor: `cd secrets && agenix -e <name>.age`
#        - non-interactive seed: `agenix-seed <name>.age <plaintext>`
#   2. List its public keys in secrets/secrets.nix.
#   3. Add an `age.secrets.<name>` block here.
#   4. Reference `config.age.secrets.<name>.path` from the consumer.
{
  inputs,
  pkgs,
  username,
  ...
}: let
  # agenix-seed — non-interactive (re-)write of an .age secret from a
  # plaintext file on disk. Wraps `rage -e` directly, recipients are
  # auto-derived from secrets/secrets.nix, the same way `agenix -e`
  # does it. Use cases:
  #   - bootstrapping a new secret without manually opening $EDITOR
  #   - automating rotation in CI / cron / scripts
  #   - sidestepping the `agenix -e + EDITOR=cp` race that hangs
  #     non-interactive runs (observed 2026-05-30, see brain journal)
  #
  # Usage: agenix-seed <basename>.age <plaintext-path>
  # Example: agenix-seed tokens.age ./tokens.txt
  agenix-seed = pkgs.writeShellApplication {
    name = "agenix-seed";
    runtimeInputs = with pkgs; [rage gnused];
    text = ''
      set -euo pipefail

      if [ "$#" -ne 2 ]; then
        cat >&2 <<EOF
      Usage: agenix-seed <basename>.age <plaintext-path>

      Reads the plaintext from <plaintext-path>, encrypts it for every
      recipient declared in secrets/secrets.nix under the basename's
      'publicKeys' entry, and writes the result to that same .age file.

      Run from /etc/nixos/secrets/ (any cwd works as long as
      secrets.nix sits next to the target .age).
      EOF
        exit 1
      fi

      target="$1"
      seed="$2"

      if [ ! -r "$seed" ]; then
        echo "agenix-seed: cannot read plaintext file '$seed'" >&2
        exit 2
      fi

      # Resolve directory holding secrets.nix. The user normally runs
      # this from /etc/nixos/secrets/, but we also accept absolute or
      # relative paths to .age files outside that dir.
      target_dir="$(dirname "$target")"
      if [ "$target_dir" = "." ]; then
        target_dir="$PWD"
      fi
      basename="$(basename "$target")"

      if [ ! -r "$target_dir/secrets.nix" ]; then
        echo "agenix-seed: $target_dir/secrets.nix not found." >&2
        echo "  Run this from the directory containing secrets.nix" >&2
        echo "  (typically /etc/nixos/secrets/)." >&2
        exit 3
      fi

      # Use nix-instantiate to evaluate publicKeys for the basename.
      # Mirrors what `agenix -e` does internally.
      readarray -t recipients < <(
        nix-instantiate --eval --strict --json -E "
          (let rules = import $target_dir/secrets.nix;
           in rules.\"$basename\".publicKeys)
        " 2>/dev/null \
          | sed -e 's/^\[//' -e 's/\]$//' -e 's/","/\n/g' -e 's/^"//' -e 's/"$//'
      )

      if [ "''${#recipients[@]}" -eq 0 ] || [ -z "''${recipients[0]:-}" ]; then
        echo "agenix-seed: no publicKeys found for '$basename' in" >&2
        echo "  $target_dir/secrets.nix" >&2
        exit 4
      fi

      # Build the rage -r argument list.
      args=()
      for r in "''${recipients[@]}"; do
        args+=(-r "$r")
      done

      out="$target_dir/$basename"
      tmp="$(mktemp --tmpdir agenix-seed.XXXXXX)"
      trap 'rm -f "$tmp"' EXIT

      rage -e "''${args[@]}" -o "$tmp" < "$seed"
      mv -f "$tmp" "$out"

      # Preserve the prior owner/mode of the .age file so git +
      # pre-commit hooks can read it. mktemp + sudo run inherit
      # root:root 0600 by default, which breaks `git diff-index`
      # ("Permission denied"). The .age content is encrypted, so
      # 0644 owner=invoker is the right resting state — same as
      # what `agenix -e` produces.
      if [ -n "''${SUDO_USER:-}" ]; then
        chown "$SUDO_USER:$(id -gn "$SUDO_USER")" "$out"
      fi
      chmod 644 "$out"

      echo "agenix-seed: wrote $out (recipients: ''${#recipients[@]})"
    '';
  };
in {
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

  # agenix CLI + agenix-seed wrapper available system-wide.
  environment.systemPackages = [
    inputs.agenix.packages.${pkgs.stdenv.hostPlatform.system}.default
    agenix-seed
  ];
}
