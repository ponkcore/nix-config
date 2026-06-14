{
  lib,
  nodejs,
  makeWrapper,
  runCommand,
}:
runCommand "context7-mcp-3.2.1" {
  nativeBuildInputs = [makeWrapper];
  meta = with lib; {
    description = "Context7 MCP server - hosted documentation lookup (stdio)";
    license = licenses.mit;
    platforms = platforms.linux;
  };
} ''
  mkdir -p $out/bin
  makeWrapper ${nodejs}/bin/npx $out/bin/context7-mcp \
    --prefix PATH : ${lib.makeBinPath [nodejs]} \
    --add-flags "-y" \
    --add-flags "@upstash/context7-mcp@3.2.1" \
    --add-flags "--transport" \
    --add-flags "stdio"
''
