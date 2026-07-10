# Aggregated overlay list — consumed by lib/mkHost.nix.
#
# Universal overlays only — pulled by every host. Host-specific
# packages (e.g. the Lecoo EC daemon) live next to their host
# composition under hosts/<name>/pkgs/ and are wired in by the
# host's default.nix via a nixpkgs.overlays entry.
#
# Adding a new universal package: drop pkgs/<name>/default.nix, add a
# line to the local-packages overlay below.
{inputs}: [
  # Cross-channel pulls — packages whose nixpkgs 26.05 version
  # is regressed or behind upstream. Each entry is a single-package
  # overlay; the rest of the system stays on the 26.05 channel.
  #
  # thunderbird 150 on Linux drops an empty `~/thunderbird/` directory
  # at every cold start. This is upstream Bug 2007074 (REOPENED at
  # time of writing): a regression from XDG basedir support landing
  # (Bug 259356) where nsXREDirProvider::GetLegacyOrXDGHomePath calls
  # EnsureDirectoryExists($HOME/thunderbird, 0700) in the XDG branch.
  # Firefox is unaffected because it builds with gAppData->profile=NULL;
  # Thunderbird sets MOZ_APP_PROFILE="thunderbird" on Linux and so
  # hits the offending branch every cold start.
  #
  # The full upstream patch by mkmelin is in r=review on Phabricator
  # (Bug 2007074 attachment 9588863, 2026-05-22) but has not landed
  # in 150.0.x. The runtime opt-out MOZ_LEGACY_HOME=1 is also read by
  # IsForceLegacyHome() and short-circuits the offending branch
  # before EnsureDirectoryExists runs — profile resolution stays at
  # ~/.thunderbird/<profile>/ exactly as today, and DBus IPC / mailto
  # handlers / OAuth / extension installs are unaffected because they
  # are not HOME-derived.
  #
  # Drop this overlay once Thunderbird 151 (with mkmelin's patch
  # landed) reaches nixpkgs 26.05.
  (_final: prev: {
    thunderbird = prev.thunderbird.overrideAttrs (old: {
      buildCommand =
        (old.buildCommand or "")
        + ''
          wrapProgram "$out/bin/thunderbird" \
            --set-default MOZ_LEGACY_HOME 1
        '';
    });
  })

  # 26.05 migration: throne, gruvbox-kvantum, Qt ABI overlay chain
  # removed — 26.05 ships throne 1.0.13 (with corrected v2 NixOS
  # patches), qtbase 6.11.1, and gruvbox-kvantum natively. No more
  # ABI mismatch between Throne and system Qt packages.

  # bun2nix overlay — required by pkgs/letta-code for fetchBunDeps
  # and the bun2nix build hook. Sourced from the letta-code flake's
  # transitive bun2nix input so the version stays in sync.
  inputs.letta-code.inputs.bun2nix.overlays.default

  # Local package derivations.
  (final: _prev: {
    cloakbrowser = final.callPackage ./cloakbrowser {};
    antigravity-cli = final.callPackage ./antigravity-cli {};
    oh-my-pi = final.callPackage ./oh-my-pi {};
    oh-my-openagent = final.callPackage ./oh-my-openagent {};

    letta-code = final.callPackage ./letta-code {inherit inputs;};
    mcp-bridge = final.callPackage ./mcp-bridge {};
    context7-mcp = final.callPackage ./context7-mcp {};
    fetch-py = final.callPackage ./fetch-py {};
  })

  # NUR — Nix User Repository (community packages, e.g. Firefox extensions).
  (_final: prev: {
    nur = import inputs.nur {
      nurpkgs = prev;
      pkgs = prev;
    };
  })
]
