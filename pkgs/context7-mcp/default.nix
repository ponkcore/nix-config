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
    hash = "sha256-l+aKVJUi5FflXhvg6PcZi9xOeF7hhGy/HhFrYQLZ1wg=";
  };

  sourceRoot = "package";

  npmDepsHash = "sha256-lVZ/+0j+8rYNH0+zD8cTfDdcwIwbQDmAjygLInrTeMM=";

  postPatch = ''
    cp ${./package-lock.json} package-lock.json
  '';

  npmBuildScript = null;
  dontNpmBuild = true;

  postInstall = ''
    wrapProgram $out/bin/context7-mcp \
      --add-flags "--transport" \
      --add-flags "stdio"
  '';

  meta = with lib; {
    description = "Context7 MCP server - hosted documentation lookup (stdio)";
    license = licenses.mit;
    platforms = platforms.linux;
  };
}
