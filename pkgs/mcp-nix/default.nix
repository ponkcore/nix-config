{
  lib,
  python313,
  uv,
  makeWrapper,
  runCommand,
}:
runCommand "mcp-nix-0.4.0" {
  nativeBuildInputs = [makeWrapper];
  meta = with lib; {
    description = "MCP server for Nixpkgs/NixOS/Home Manager (felixdorn/mcp-nix)";
    license = licenses.gpl3Plus;
    platforms = platforms.linux;
  };
} ''
  mkdir -p $out/bin
  makeWrapper ${uv}/bin/uvx $out/bin/mcp-nix \
    --prefix PATH : ${lib.makeBinPath [python313 uv]} \
    --add-flags "--python" \
    --add-flags "${python313}/bin/python3.13" \
    --add-flags "mcp-nix==0.4.0"
''
