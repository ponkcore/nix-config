{
  lib,
  buildNpmPackage,
  fetchurl,
}:
buildNpmPackage rec {
  pname = "context7-mcp";
  version = "3.2.1";

  src = fetchurl {
    url = "https://registry.npmjs.org/@upstash/context7-mcp/-/context7-mcp-${version}.tgz";
    hash = "sha512-ZVh1OAeOd5C4ORvPKYUgZSIwm+ofmofLyXS8p2Vvm0WH29axgNwhcc7sCr3aMzNX7oPKL9zH+1lb17W+AeMKtQ==";
  };

  npmDepsHash = "sha256-habUQTjfpFrq5KuixEnrzGS7Xc+RjnpF1LaGxr+yFTs=";

  postPatch = ''
    cp ${./package-lock.json} package-lock.json
  '';

  buildPhase = ''
    runHook preBuild
    npm run build || true
    runHook postBuild
  '';

  meta = with lib; {
    description = "Context7 MCP server — hosted documentation lookup";
    license = licenses.mit;
    platforms = platforms.linux;
  };
}
