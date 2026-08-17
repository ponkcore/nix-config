# NixOS 26.05 — Universal Agent Rules

You are operating on **NixOS 26.05**. This is NOT a standard Linux
distribution. Standard package management commands DO NOT WORK here.
Read this file fully before taking any action that involves
installing software, running build tools, or executing binaries.

## What NOT to do (and why)

| Command | Why it fails | What to do instead |
|---------|-------------|-------------------|
| `pip install <pkg>` | PEP 668: Python is in immutable /nix/store | Create venv inside devShell |
| `pip install --user <pkg>` | No writable user site-packages on NixOS | Create venv inside devShell |
| `npm install -g <pkg>` | No writable global npm prefix | `npx <pkg>` or `nix shell nixpkgs#nodePackages.<pkg>` |
| `yarn global add <pkg>` | Same as npm -g | `nix shell nixpkgs#nodePackages.<pkg>` |
| `pnpm add -g <pkg>` | Same as npm -g | `nix shell nixpkgs#nodePackages.<pkg>` |
| `apt install <pkg>` | apt does not exist on NixOS | `nix shell nixpkgs#<pkg>` |
| `brew install <pkg>` | brew does not exist on NixOS | `nix shell nixpkgs#<pkg>` |
| `pacman -S <pkg>` | pacman does not exist on NixOS | `nix shell nixpkgs#<pkg>` |
| `nix-env -i <pkg>` | Imperative, breaks reproducibility | Add to flake.nix devShell |
| `nix profile install` | Imperative, breaks reproducibility | Add to flake.nix devShell |
| `nix flake update` | Changes all inputs + lock graph (NOT read-only) | Treat as dependency-update task |
| `nix-collect-garbage -d` | Destroys old generations + rollback capability | Never without explicit user approval |
| `./downloaded-binary` | ELF interpreter missing (nix-ld may help) | See FHS binary procedure below |
| `#!/bin/bash` in scripts | /bin/bash does not exist on NixOS | Use `#!/usr/bin/env bash` |

## Security and system boundary

- **Read `.envrc` before running `direnv allow`.** `.envrc` is
  executable code from the repository — inspect it first.
- **Never place secrets** in Nix expressions, `flake.lock`,
  `/nix/store` (world-readable), build logs, or instruction files.
  Use agenix, sops-nix, or runtime secret injection.
- **Never change Nix cache keys, substituters, trusted-users, or
  signature policy** (`require-sigs`) as a build workaround. These
  are security boundaries.
- **Do not create `flake.nix`** unless the task requires a project
  dev environment. `shell.nix`, `npins`, and plain Nix expressions
  are valid alternatives. Flakes are one option, not the default.
- **System administration** (`/etc/nixos`, `nixos-rebuild`, system
  services, profiles, remote deployment, garbage collection) belongs
  to the system administrator agent. Do not attempt these operations.

## Entering the development environment

Before running ANY build, install, or test command:

1. Check if `flake.nix` exists in the project root.
   - If yes AND `.envrc` exists: **read `.envrc` first**, then run
     `direnv allow` (one-time per project).
   - If yes but no `.envrc`: run `nix develop` to enter the devShell.
   - If neither: use `nix shell nixpkgs#<package>` for individual tools.
2. Never assume tools are in PATH. Run `which gcc` / `which python`
   / `which node` first.

## Ad-hoc tool installation

```sh
nix shell nixpkgs#<package-name> --command <tool> <args>
```

Common mappings: gcc→`nixpkgs#gcc`, make→`nixpkgs#gnumake`,
python3→`nixpkgs#python3`, node→`nixpkgs#nodejs_22`, jq→`nixpkgs#jq`.

## FHS binary procedure

When a downloaded binary fails with "No such file or directory"
despite the file existing and being executable:

1. nix-ld is enabled system-wide — the binary may just work.
2. `steam-run ./binary` (no config change needed).
3. `patchelf --set-interpreter ...` (for repeated scripted use).

**If this is a permanent tool, package it in Nix** instead of
patching the binary indefinitely. See the `nixos-constraints` skill
for detailed procedures.

## devShell templates

Templates for standard stacks (Python, Node, Rust, Go, polyglot)
are at `~/.local/share/nixos-templates/`. Copy to project root and
modify the copy — never edit the template path (read-only Nix store).
For non-standard stacks, write `flake.nix` from scratch.

## Writing scripts

Always use `#!/usr/bin/env bash` (not `#!/bin/bash`),
`#!/usr/bin/env python3`, `#!/usr/bin/env node`.

## When in doubt

```sh
nix shell nixpkgs#<package-name>
```

Search: `nix search nixpkgs <keyword>`

For error recovery procedures (pip, npm, ELF binaries, gcc, cargo,
direnv, flake lock vs update, garbage collection), invoke the
`nixos-constraints` skill.
