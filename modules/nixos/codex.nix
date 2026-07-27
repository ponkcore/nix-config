# codex.nix — system-wide defaults for OpenAI Codex CLI.
#
# Codex merges this low-precedence layer with the mutable user config under
# ~/.codex. The system layer owns only the shared MCP stack; model choice,
# reasoning effort, project trust, authentication, and sessions stay per-user.
{pkgs, ...}: let
  codexMcpConfig = pkgs.formats.toml {};
  codexSystemConfig = codexMcpConfig.generate "codex-config.toml" {
    mcp_servers = {
      context7 = {
        command = "${pkgs.context7-mcp}/bin/context7-mcp";
        env_vars = ["CONTEXT7_API_KEY"];
        startup_timeout_sec = 30;
        tool_timeout_sec = 120;
      };

      github = {
        command = "${pkgs.github-mcp-server}/bin/github-mcp-server";
        args = ["stdio" "--toolsets=default,code_security,secret_protection"];
        env_vars = ["GITHUB_PERSONAL_ACCESS_TOKEN"];
        startup_timeout_sec = 30;
        tool_timeout_sec = 120;
      };

      nixos-options = {
        command = "${pkgs.mcp-nixos}/bin/mcp-nixos";
        startup_timeout_sec = 30;
        tool_timeout_sec = 120;
      };

      omniroute = {
        url = "https://mcp.infinitycore.space:8443/omp/sse";
        env_http_headers.X-Proxy-Key = "OMP_PROXY_KEY";
        enabled_tools = ["web_search" "web_fetch"];
        startup_timeout_sec = 90;
        tool_timeout_sec = 120;
      };

      repomix = {
        command = "${pkgs.repomix}/bin/repomix";
        args = ["--mcp"];
        startup_timeout_sec = 30;
        tool_timeout_sec = 120;
      };

      semgrep = {
        command = "${pkgs.semgrep}/bin/semgrep";
        args = ["mcp"];
        startup_timeout_sec = 30;
        tool_timeout_sec = 120;
      };
    };
  };
in {
  environment.etc."codex/config.toml".source = codexSystemConfig;
}
