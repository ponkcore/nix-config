# home/agent-rules.nix — global NixOS rules for AI coding agents.
#
# Deploys a shared AGENTS.md to each agent's global instruction path,
# devShell templates as read-only references, and a nixos-constraints
# skill for opencode/omo.
#
# Research: 2026-07-04-agent-global-instructions-verification.result.md
# Path verification (22 sources):
#   opencode  → ~/.config/opencode/AGENTS.md  (xdg.configFile)
#   omp       → ~/.omp/agent/AGENTS.md        (home.file)
#   agy       → ~/.gemini/GEMINI.md           (home.file)
# ~/.agents/AGENTS.md — NOT deployed (not read by opencode or agy;
#   omp reads it only as priority-70 fallback, shadowed by native
#   priority 100 at ~/.omp/agent/AGENTS.md).
_: let
  # Single source of truth — all agents get identical content.
  sharedRules = ./agent-instructions/AGENTS.md;

  # DevShell templates — read-only Nix store references.
  # Agents copy them to project root and modify the copy.
  templates = ./agent-instructions/templates;
in {
  # ── Global AGENTS.md deployment ──────────────────────────────

  # opencode/omo: ~/.config/opencode/AGENTS.md
  xdg.configFile."opencode/AGENTS.md".source = sharedRules;

  # omp: ~/.omp/agent/AGENTS.md (native provider, priority 100)
  home.file.".omp/agent/AGENTS.md".source = sharedRules;

  # agy: ~/.gemini/GEMINI.md
  # NOTE: agy's /memory add command writes to this file at runtime.
  # If /memory add is used, this symlink will cause EROFS. Currently
  # agy is rarely used on this system. If usage increases, switch to
  # home.activation guard (write only if file does not exist).
  home.file.".gemini/GEMINI.md".source = sharedRules;

  # ── nixos-constraints skill (opencode/omo only) ─────────────
  # On-demand error recovery procedures. Invoked when agents hit
  # NixOS-specific failures (pip, npm -g, binary EROFS, etc.).
  # omp/agy have no confirmed skill-trigger mechanism — error
  # procedures live in the global AGENTS.md for those agents.
  xdg.configFile."opencode/skill/nixos-constraints/SKILL.md".source =
    ./agent-instructions/nixos-constraints/SKILL.md;

  # ── DevShell templates (read-only references) ────────────────
  # Deployed to a shared path accessible by all agents.
  # Agents copy the relevant template to the project root and
  # modify the copy — never edit the template path directly.
  home.file.".local/share/nixos-templates/python-flake.nix".source = "${templates}/python/flake.nix";
  home.file.".local/share/nixos-templates/node-flake.nix".source = "${templates}/node/flake.nix";
  home.file.".local/share/nixos-templates/rust-flake.nix".source = "${templates}/rust/flake.nix";
  home.file.".local/share/nixos-templates/go-flake.nix".source = "${templates}/go/flake.nix";
  home.file.".local/share/nixos-templates/polyglot-flake.nix".source = "${templates}/polyglot/flake.nix";
  home.file.".local/share/nixos-templates/envrc".source = "${templates}/envrc";
}
