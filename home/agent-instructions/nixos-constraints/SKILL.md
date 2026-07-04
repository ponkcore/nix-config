---
name: nixos-constraints
description: >
  NixOS 26.05 development constraints and error recovery procedures.
  Invoke when: pip install fails, npm install -g fails, a downloaded
  binary produces "No such file or directory", gcc/make/node/python is
  not found, or any command fails with a path not found under /usr/bin
  or /lib.
allowed-tools:
  - Bash
  - Read
  - Write
  - AskUserQuestion
---

# NixOS Development Constraints

## When to invoke this skill

Invoke this skill when you encounter ANY of the following:

- `error: externally-managed-environment` from pip
- `OSError: [Errno 30] Read-only file system` from pip
- `EACCES: permission denied` from npm install -g
- `bash: ./binary: No such file or directory` (binary exists but won't run)
- `command not found: gcc` / `command not found: make` / `command not found: python`
- `error: linker 'cc' not found` from cargo
- `bad interpreter: /bin/bash: no such file or directory`
- `Package <X> not found` from pkg-config
- Any attempt to use `apt`, `brew`, `pacman`, `yum`

## Diagnostic procedure

### Step 1: Identify the error category

```bash
# Check if you are on NixOS
cat /etc/os-release | grep -i nix
# Expected: NAME="NixOS"
```

### Step 2: Check for devShell

```bash
# Is there a flake.nix?
ls flake.nix 2>/dev/null && echo "flake.nix found" || echo "no flake.nix"

# Is direnv active?
echo "$DIRENV_DIR"

# Is a devShell active?
echo "$IN_NIX_SHELL"
```

### Step 3: Enter the devShell

```bash
# If flake.nix exists and .envrc exists:
direnv allow

# If flake.nix exists but no .envrc:
nix develop

# If neither exists, use nix shell for the specific tool:
# nix shell nixpkgs#<package>
```

### Step 4: Error-specific fixes

#### pip install fails

```bash
# Inside devShell:
python -m venv .venv
source .venv/bin/activate
pip install <pkg>
# OR use uv:
uv pip install <pkg>
```

#### npm install -g fails

```bash
# Use npx instead:
npx <pkg>
# OR set a writable prefix:
export npm_config_prefix="$HOME/.npm-global"
export PATH="$HOME/.npm-global/bin:$PATH"
npm install -g <pkg>
```

#### Downloaded binary won't run

```bash
# Option 1: nix-ld is enabled system-wide — the binary should just work.
# If it does not, proceed to Option 2.

# Option 2: steam-run
steam-run ./binary

# Option 3: patchelf
patchelf --set-interpreter "$(patchelf --print-interpreter "$(which ls)")" ./binary
./binary
```

#### gcc / make not found

```bash
nix shell nixpkgs#gcc nixpkgs#gnumake --command make
# OR add to devShell buildInputs: pkgs.gcc pkgs.gnumake
```

#### pkg-config: Package not found

The package's `.dev` output must be in the devShell:

```nix
buildInputs = [ pkgs.openssl.dev pkgs.zlib.dev ];
```

#### cargo: linker 'cc' not found

The devShell is missing `pkgs.gcc`. Add it to `buildInputs`.

## Universal fallback

When you need any tool not in PATH:

```bash
nix shell nixpkgs#<package-name> --command <tool> <args>
```

Search for package names:

```bash
nix search nixpkgs <keyword>
```

## Writing scripts on NixOS

Always use:

- `#!/usr/bin/env bash` (not `#!/bin/bash`)
- `#!/usr/bin/env python3` (not `#!/usr/bin/python3`)
- `#!/usr/bin/env node` (not `#!/usr/bin/node`)

## Writing CI pipelines

Target `ubuntu-latest` runners. Use Nix in CI:

```yaml
- uses: cachix/install-nix-action@v27
  with:
    extra_nix_config: "experimental-features = nix-command flakes"
- run: nix develop --command make test
```
