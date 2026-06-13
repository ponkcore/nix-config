{
  lib,
  python3,
  makeWrapper,
  runCommand,
}:
runCommand "mcp-bridge-1.0.0" {
  nativeBuildInputs = [makeWrapper];
  meta = with lib; {
    description = "One-shot stdio MCP tool caller for Letta Code skills";
    license = licenses.mit;
    platforms = platforms.unix;
  };
} ''
  install -Dm755 ${./mcp-bridge.py} $out/bin/mcp-bridge
  wrapProgram $out/bin/mcp-bridge --prefix PATH : ${lib.makeBinPath [python3]}
''
