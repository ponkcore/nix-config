# tests/secrets.nix — exercises the agenix decryption pipeline.
#
# The production secret (secrets/omniroute-key.age) is encrypted to
# the live host's SSH ed25519 key, which the test VM does not have.
# Reusing the production wiring would just fail at activation. So
# the test:
#   1. Builds a throwaway fixtures derivation that ssh-keygens a
#      fresh ed25519 pair and encrypts a tiny KEY=VALUE plaintext to
#      the public half via rage.
#   2. Boots a NixOS VM that imports the agenix NixOS module, points
#      `age.identityPaths` at the throwaway private key, and declares
#      one `age.secrets.test-secret` entry pointing at the encrypted
#      payload.
#   3. Asserts at runtime that /run/agenix/test-secret materialises
#      with the expected content, mode (400), and owner.
#
# This is a real end-to-end check of the same code paths
# modules/nixos/secrets.nix uses on production hosts: agenix CLI,
# activation script, /run/agenix mount, ownership chown. The fixtures
# derivation is intentionally non-deterministic (each ssh-keygen run
# yields a different pair); that costs us a build-cache miss per
# rebuild but means no test key material ever lands in the repo.
{
  pkgs,
  inputs,
}: let
  fixtures =
    pkgs.runCommand "talos-test-fixtures" {
      nativeBuildInputs = [pkgs.openssh pkgs.rage];
    } ''
      mkdir -p $out
      # ed25519 host key, no passphrase, deterministic filename so
      # the VM module can reference $out/host_key directly.
      ssh-keygen -t ed25519 -N "" -C "talos-test-fixture" -f $out/host_key
      # Encrypt a tiny KEY=VALUE plaintext to that pubkey. age accepts
      # OpenSSH ed25519 public keys directly as recipients.
      printf 'TALOS_TEST_KEY=hello-from-test\n' \
        | rage -a -e -R $out/host_key.pub -o $out/secret.age
    '';
in
  pkgs.testers.runNixOSTest {
    name = "talos-secrets";

    nodes.machine = {...}: {
      imports = [inputs.agenix.nixosModules.default];

      age = {
        identityPaths = ["${fixtures}/host_key"];
        secrets.test-secret = {
          file = "${fixtures}/secret.age";
          owner = "oonishi";
          mode = "400";
        };
      };

      # Minimal user matching the secret owner. Keep the account
      # lightweight: no shell choice, no extra groups — that is the
      # job of tests/users.nix.
      users.users.oonishi = {
        isNormalUser = true;
        uid = 1000;
      };
    };

    testScript = ''
      machine.wait_for_unit("multi-user.target")

      # The secret materialised under /run/agenix.
      machine.succeed("test -f /run/agenix/test-secret")
      machine.succeed("test -s /run/agenix/test-secret")

      # Permissions and ownership match the declaration.
      mode = machine.succeed("stat -c %a /run/agenix/test-secret").strip()
      assert mode == "400", f"expected mode 400, got {mode}"
      owner = machine.succeed("stat -c %U /run/agenix/test-secret").strip()
      assert owner == "oonishi", f"expected owner oonishi, got {owner}"

      # Content round-tripped through age decryption.
      machine.succeed(
          "grep -q '^TALOS_TEST_KEY=hello-from-test$' /run/agenix/test-secret"
      )
    '';
  }
