{
  lib,
  python3,
  makeWrapper,
  runCommand,
}:
runCommand "fetch-py-1.0.0" {
  nativeBuildInputs = [makeWrapper];
  meta = with lib; {
    description = "Guarded web fetch for talos (python3 stdlib, SSRF-protected)";
    license = licenses.mit;
    platforms = platforms.unix;
  };
} ''
  install -Dm755 ${./fetch.py} $out/bin/fetch.py
  wrapProgram $out/bin/fetch.py --prefix PATH : ${lib.makeBinPath [python3]}
''
