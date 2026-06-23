# oh-my-openagent — OpenCode plugin packaged for file:// loading.
# OpenCode treats absolute/file:// plugin specs as local plugins and skips
# Npm.add(), so this package vendors the npm dependency closure into /nix/store
# instead of letting OpenCode install it into mutable cache at startup.
{
  buildNpmPackage,
  fetchurl,
}: let
  pname = "oh-my-openagent";
  version = "4.13.0";
in
  buildNpmPackage {
    inherit pname version;

    src = fetchurl {
      url = "https://registry.npmjs.org/oh-my-openagent/-/oh-my-openagent-${version}.tgz";
      hash = "sha256-2cmMqLkHGZMyJK7rutUM3Om5cTJ9v11Iwb/X4sX0LC4=";
    };

    sourceRoot = "package";

    npmDepsHash = "sha256-jMqqFJcX3h55h631lJdqlBQOOB60ui3qAZxs0OpUlJs=";

    prePatch = ''
      cp ${./package.json} package.json
      cp ${./package-lock.json} package-lock.json
    '';

    npmBuildScript = null;
    dontNpmBuild = true;

    npmInstallFlags = ["--ignore-scripts"];

    meta = {
      description = "Batteries-included OpenCode plugin with multi-agent orchestration";
      homepage = "https://github.com/code-yeongyu/oh-my-openagent";
      license = {
        fullName = "Sustainable Use License v1.0";
        url = "https://github.com/code-yeongyu/oh-my-openagent/blob/dev/LICENSE.md";
        free = false;
      };
      platforms = ["x86_64-linux"];
    };
  }
