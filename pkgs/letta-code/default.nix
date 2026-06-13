{
  inputs,
  lib,
  pkgs,
}: let
  source = inputs.letta-code;
  packageJson = builtins.fromJSON (builtins.readFile "${source}/package.json");
in
  pkgs.stdenv.mkDerivation rec {
    pname = "letta-code";
    inherit (packageJson) version;
    src = source;

    bunDeps = pkgs.bun2nix.fetchBunDeps {
      bunNix = ./bun.nix;
    };

    nativeBuildInputs = [
      pkgs.nodejs_22
      pkgs.bun
      pkgs.makeWrapper
      pkgs.pkg-config
      pkgs.python3
      pkgs.bun2nix.hook
    ];

    bunInstallFlags = ["--linker=hoisted"];

    CI = "true";

    dontUseBunCheck = true;

    preBuild = ''
      export HOME="$TMPDIR"
      substituteInPlace build.js \
        --replace-fail 'await Bun.$`bunx tsc -p tsconfig.types.json`' 'true'
    '';

    buildPhase = ''
      runHook preBuild
      bun run build
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      pack_dir="$TMPDIR/package"
      mkdir -p "$pack_dir" "$out/lib/letta-code" "$out/bin"

      npm pack --ignore-scripts --pack-destination "$pack_dir"
      tar -xzf "$pack_dir"/letta-ai-letta-code-*.tgz \
        -C "$out/lib/letta-code" \
        --strip-components=1

      cp -rL node_modules "$out/lib/letta-code/node_modules"

      makeWrapperArgs=(
        --add-flags "$out/lib/letta-code/letta.js"
        --prefix PATH : ${lib.makeBinPath [pkgs.git pkgs.ripgrep]}
      )
      makeWrapperArgs+=(--prefix LD_LIBRARY_PATH : ${pkgs.stdenv.cc.cc.lib}/lib)
      makeWrapper ${pkgs.bun}/bin/bun "$out/bin/letta" "''${makeWrapperArgs[@]}"

      runHook postInstall
    '';

    postInstall = ''
      chmod +x "$out/bin/letta"
    '';

    meta = {
      inherit (packageJson) description;
      homepage = "https://github.com/letta-ai/letta-code";
      license = lib.licenses.asl20;
      mainProgram = "letta";
    };
  }
