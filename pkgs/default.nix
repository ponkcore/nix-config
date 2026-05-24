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
  # Cross-channel pulls — packages whose stable release in nixos-25.11
  # is regressed or behind upstream. Each entry is a single-package
  # rebind to nixos-unstable; the rest of the system stays on stable.
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
  # landed) reaches nixos-25.11 / nixos-unstable.
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

  # throne (1.0.8-unstable-2025-10-29 on 25.11): the v1 NixOS patch
  # injected by nixpkgs makes TUN mode unusable — the GUI shows
  # "Unable to elevate privileges when installed with Nix" because
  # the patched FindCoreRealPath redirect collides with upstream
  # changes. nixpkgs commit d380eba (2026-01-25) bumped to 1.0.13
  # and rewrote both NixOS patches as v2 against the new source
  # tree; that fix lives on nixos-unstable, not on 25.11. Drop this
  # rebind once 25.11 receives the backport.
  #
  # Throne 1.0.13 from unstable is built against qtbase-6.11.0
  # whereas 25.11's gruvbox-kvantum and qt6ct ship qtbase-6.10.2,
  # which makes Qt's plugin loader reject them at runtime
  # (build-version mismatch). To keep the in-app Theme picker
  # actually working, also pull qtstyleplugin-kvantum, qt6ct and
  # gruvbox-kvantum from unstable so all three end up on the same
  # qtbase ABI as Throne.
  (final: _prev: let
    pkgsUnstable = import inputs.nixpkgs-unstable {
      inherit (final.stdenv.hostPlatform) system;
      inherit (final) config;
    };
  in {
    inherit (pkgsUnstable) throne gruvbox-kvantum;
    qt6Packages =
      _prev.qt6Packages
      // {
        inherit (pkgsUnstable.qt6Packages) qt6ct qtstyleplugin-kvantum;
      };
  })

  # Local package derivations.
  (final: _prev: {
    donutbrowser = final.callPackage ./donutbrowser {};
    devin-cli = final.callPackage ./devin-cli {};
    orbit = final.callPackage ./orbit {};

    # gptme — terminal-first AI agent built from the upstream Poetry
    # project. poetry2nix is constructed against the host pkgs set
    # (`final`) so the resulting Python interpreter and runtime
    # libraries come from nixpkgs-25.11; only the build glue is
    # poetry2nix's own. See pkgs/gptme/default.nix for the closure
    # rationale and pkgs/gptme/update.sh for the bump workflow.
    gptme = let
      poetry2nix = inputs.poetry2nix.lib.mkPoetry2Nix {pkgs = final;};
    in
      final.callPackage ./gptme {
        inherit (poetry2nix) mkPoetryApplication;
      };
  })

  # NUR — Nix User Repository (community packages, e.g. Firefox extensions).
  (_final: prev: {
    nur = import inputs.nur {
      nurpkgs = prev;
      pkgs = prev;
    };
  })
]
