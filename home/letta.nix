# home/letta.nix — Letta Code memory-first agent.
#
# Replaces gptme as the talos agent runtime (see
# decisions/0015-migrate-to-letta-code.md).
#
# Phase 2 (installation): adds the letta binary via
# programs.letta-code, imports the upstream HM module.
# Env vars and fish wrapper come in Phase 3/6.
{inputs, ...}: {
  imports = [inputs.letta-code.homeManagerModules.default];

  programs.letta-code.enable = true;
}
