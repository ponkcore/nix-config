# codex.nix — official OpenAI Codex CLI prebuilt and credential launcher.
#
# The pinned upstream release avoids a local Rust build. System-wide MCP
# definitions live in modules/nixos/codex.nix; mutable Codex state remains
# under ~/.codex. Secrets enter only the launcher environment.
{pkgs, ...}: let
  version = "0.151.0";
  codexPackage = pkgs.stdenvNoCC.mkDerivation {
    pname = "codex";
    inherit version;

    src = pkgs.fetchurl {
      url = "https://github.com/openai/codex/releases/download/rust-v${version}/codex-package-x86_64-unknown-linux-musl.tar.gz";
      hash = "sha256-bjWsYLhsDox/i895e+i5IgYZn2JTIAtm/wVHJ2+M+lw=";
    };

    sourceRoot = ".";
    dontBuild = true;

    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      cp -r bin codex-path codex-resources codex-package.json "$out/"
      runHook postInstall
    '';

    meta = {
      description = "OpenAI Codex CLI";
      homepage = "https://github.com/openai/codex";
      license = pkgs.lib.licenses.asl20;
      mainProgram = "codex";
      platforms = ["x86_64-linux"];
      sourceProvenance = [pkgs.lib.sourceTypes.binaryNativeCode];
    };
  };
  codexLauncher = pkgs.writeShellScriptBin "codex" ''
    export PATH=${pkgs.lib.makeBinPath [pkgs.bubblewrap]}:$PATH

    set -o allexport
    if [[ -r /run/agenix/tokens ]]; then
      source /run/agenix/tokens
    fi
    set +o allexport

    if command -v gh >/dev/null 2>&1; then
      GITHUB_PERSONAL_ACCESS_TOKEN="$(gh auth token 2>/dev/null || true)"
      export GITHUB_PERSONAL_ACCESS_TOKEN
    fi

    exec ${codexPackage}/bin/codex "$@"
  '';
in {
  home.packages = [codexLauncher];
}
