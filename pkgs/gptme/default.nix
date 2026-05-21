# gptme — terminal-first AI agent (https://gptme.org).
#
# Built from the upstream Poetry project via poetry2nix. gptme is not
# in nixpkgs as of 25.11; we maintain a local derivation pinned by
# manifest.json and bumped by update.sh.
#
# Layering:
#   - Source: fetchFromGitHub at the rev/hash recorded in manifest.json.
#     The tarball already contains poetry.lock — no vendoring needed.
#   - PEP 621 patch: gptme's pyproject.toml puts the project name in
#     [project] (modern PEP 621 style) but poetry2nix v0.x still reads
#     `${pyProject.tool.poetry.name}` (poetry-legacy style) and crashes
#     with "attribute 'name' missing" when it isn't set there. We
#     materialise a patched source tree via runCommand that injects
#     `name = "gptme"` right under the existing [tool.poetry] header
#     before poetry2nix sees the file. Drop this layer once
#     nix-community/poetry2nix#1820 is fixed upstream.
#   - Build: poetry2nix.mkPoetryApplication with python312. The default
#     `extras = []` keeps the closure tight: TUI + shell + LLM providers
#     work, but heavy optional groups (datascience, tts, dspy, eval,
#     telemetry, youtube, browser/playwright, pyinstaller) are excluded.
#     If a future task needs e.g. browser tooling, add it explicitly to
#     `extras` here rather than enabling `all` — that group pulls 30+
#     packages including playwright, which itself wants `playwright
#     install` at runtime.
#
# Bumping: ./update.sh v0.XX.X — rewrites manifest.json with the new
# rev and prefetched hash. Always run nixos-rebuild test afterwards;
# poetry2nix occasionally needs new override hooks for upstream deps
# that change build systems (most fail loudly with a missing-build-
# input error which the override list addresses).
{
  lib,
  mkPoetryApplication,
  python312,
  fetchFromGitHub,
  runCommand,
}: let
  manifest = lib.importJSON ./manifest.json;
  rawSrc = fetchFromGitHub {
    inherit (manifest.src) owner repo rev hash;
  };
  # See header comment for why this patch exists.
  patchedSrc = runCommand "gptme-${manifest.version}-src" {} ''
    cp -r ${rawSrc} $out
    chmod -R u+w $out
    sed -i '/^\[tool\.poetry\]$/a name = "gptme"\nversion = "${manifest.version}"' $out/pyproject.toml

    # Demote the "Audio not available, skipping ding sound playback"
    # log line from INFO to DEBUG. gptme has no audio backend in our
    # headless setup, so the line fires on every prompt; it serves no
    # purpose for the user. Drop this when gptme demotes it upstream.
    sed -i 's|log.info("Audio not available, skipping ding sound playback")|log.debug("Audio not available, skipping ding sound playback")|' \
      $out/gptme/util/sound.py
  '';
in
  mkPoetryApplication {
    projectDir = patchedSrc;
    python = python312;
    extras = [];

    # poetry2nix master (rev ce2369d) still calls
    # `rustPlatform.fetchCargoTarball` for rpds-py / cryptography /
    # bcrypt / pycrdt overrides, but the helper was removed in
    # nixpkgs-25.05 in favour of `fetchCargoVendor`. Easier than
    # patching every override individually: prefer pre-built manylinux
    # wheels for the affected packages so the rust-build path is never
    # taken. Pure-python packages still build from source. Drop this
    # workaround once poetry2nix completes its fetchCargoVendor
    # migration (issue: nix-community/poetry2nix#1820).
    preferWheels = true;

    # Run only a smoke import in the build sandbox; gptme's full test
    # suite hits live LLM endpoints and is unsuitable for offline CI.
    doCheck = false;

    meta = {
      description = "Terminal-first AI agent with shell, code execution, file editing, web browsing";
      homepage = "https://gptme.org";
      license = lib.licenses.mit;
      mainProgram = "gptme";
      platforms = lib.platforms.linux;
      inherit (manifest) version;
    };
  }
