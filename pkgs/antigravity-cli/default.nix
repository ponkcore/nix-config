{
  lib,
  stdenv,
  fetchzip,
  autoPatchelfHook,
}: let
  version = "1.0.6";

  sourceData = {
    "x86_64-linux" = {
      url = "https://storage.googleapis.com/antigravity-public/antigravity-cli/1.0.6-5359777384103936/linux-x64/cli_linux_x64.tar.gz";
      hash = "sha256-rxDLuuium+yQl3SiRcFhLzC5+ZCZU/tG2LQfFZMOYx4=";
    };
    "aarch64-linux" = {
      url = "https://storage.googleapis.com/antigravity-public/antigravity-cli/1.0.6-5359777384103936/linux-arm/cli_linux_arm64.tar.gz";
      hash = "sha256-Mol5V3Lt2A89yrGdwWiOdv4y5dCZkMaT8onXG6IsQtc=";
    };
  };

  source =
    sourceData.${stdenv.hostPlatform.system}
      or (throw "Unsupported system: ${stdenv.hostPlatform.system}");
in
  stdenv.mkDerivation {
    pname = "antigravity-cli";
    inherit version;

    src = fetchzip {
      inherit (source) url hash;
    };

    strictDeps = true;

    nativeBuildInputs = lib.optionals stdenv.isLinux [autoPatchelfHook];

    dontBuild = true;
    dontConfigure = true;

    installPhase = ''
      runHook preInstall
      install -Dm755 antigravity $out/bin/agy
      runHook postInstall
    '';

    meta = {
      description = "Google's Go-based terminal user interface (TUI) agent client";
      homepage = "https://antigravity.google";
      license = lib.licenses.unfree;
      platforms = lib.attrNames sourceData;
      mainProgram = "agy";
    };
  }
