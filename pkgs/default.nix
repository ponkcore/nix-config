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
  # Local package derivations.
  (final: _prev: {
    donutbrowser = final.callPackage ./donutbrowser {};
    devin-cli = final.callPackage ./devin-cli {};

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
