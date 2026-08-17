---
name: nixos-constraints
description: >
  NixOS 26.05 development constraints and error recovery procedures.
  Invoke when: pip install fails, npm install -g fails, a downloaded
  binary produces "No such file or directory", gcc/make/node/python is
  not found, cargo linker fails, direnv trust is unclear, flake lock
  vs update is ambiguous, garbage collection is considered, or any
  command fails with a path not found under /usr/bin or /lib.
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
- Uncertainty about whether to run `direnv allow`
- Uncertainty about `nix flake lock` vs `nix flake update`
- Consideration of `nix-collect-garbage` or `nix-collect-garbage -d`
- Uncertainty about whether to create a `flake.nix`

## Diagnostic procedure

### Step 1: Identify the error category

```bash
cat /etc/os-release | grep -i nix   # Expected: NAME="NixOS"
```

### Step 2: Check for devShell

```bash
ls flake.nix 2>/dev/null && echo "flake.nix found" || echo "no flake.nix"
echo "$DIRENV_DIR"    # direnv active?
echo "$IN_NIX_SHELL"  # devShell active?
```

### Step 3: Enter the devShell

```bash
# If flake.nix + .envrc exist: READ .envrc FIRST, then:
direnv allow

# If flake.nix exists but no .envrc:
nix develop

# If neither exists:
nix shell nixpkgs#<package>
```

## direnv trust procedure

`.envrc` is executable code from the repository. Before running
`direnv allow`:

1. **Read** the `.envrc` file.
2. **Evaluate**: does it only set up a Nix devShell (`use flake`,
   `use nix`, `eval "$(nix ...)"`) or does it run unexpected commands?
3. **Allow** only if the content is trusted:
   ```bash
   direnv allow
   ```
4. If untrusted: do not allow. Use `nix develop` instead.

## flake lock vs flake update

These are NOT the same operation:

- `nix flake lock` — creates `flake.lock` if absent; does NOT
  update existing locked inputs. Safe to run.
- `nix flake update` — updates ALL inputs to latest. Changes
  `flake.lock`. Treat as a dependency-update task, not a
  diagnostic step.
- `nix flake update --input <name>` — updates one input. Still
  modifies lock graph.

Never run `nix flake update` as a troubleshooting step.

## garbage collection warning

`nix-collect-garbage -d` destroys:
- Old system generations (rollback capability lost)
- Unreferenced store paths (old package versions)

Never run without explicit user approval. For safe cleanup:

```bash
# Remove only unreferenced paths older than 30 days:
nix-collect-garbage --delete-older-than 30d
```

## flake.nix creation guidance

Create `flake.nix` only when the project genuinely needs a
reproducible devShell with multiple dependencies. Alternatives:

- `shell.nix` — simpler, no flake overhead
- `nix shell nixpkgs#<pkg>` — ad-hoc, no file needed
- `npins` — alternative pinning without flakes

If creating `flake.nix` from a template, copy from
`~/.local/share/nixos-templates/` and modify the copy.

## Error-specific fixes

### pip install fails

```bash
# Inside devShell:
python -m venv .venv
source .venv/bin/activate
pip install <pkg>
# OR: uv pip install <pkg>
```

Never run pip outside an activated venv on NixOS.

### npm install -g fails

```bash
# Use npx (no global install needed):
npx <tool>

# Or use nix shell for repeated access:
nix shell nixpkgs#nodePackages.<pkg>
```

Do NOT set a global npm prefix (`npm_config_prefix`). That is an
imperative install and breaks reproducibility.

### Downloaded binary won't run (FHS triage)

First determine: is this a temporary dev tool or a permanent tool?

**Temporary binary** (one-off use):
```bash
# Option 1: nix-ld is enabled system-wide — may just work.
# Option 2: steam-run
steam-run ./binary
```

**Permanent tool** (repeated use): package it in Nix instead of
patching indefinitely. Use `patchelf` only as a bridge:
```bash
patchelf --set-interpreter "$(patchelf --print-interpreter "$(which ls)")" ./binary
```

### gcc / make not found

```bash
nix shell nixpkgs#gcc nixpkgs#gnumake --command make
# OR add to devShell: pkgs.gcc pkgs.gnumake
```

### pkg-config: Package not found

The package's `.dev` output must be in the devShell:

```nix
buildInputs = [ pkgs.openssl.dev pkgs.zlib.dev ];
```

### cargo: linker 'cc' not found

The devShell is missing `pkgs.gcc`. Add it to `buildInputs`.

### Rust procedure

```bash
nix develop    # devShell must have cargo, rustc, gcc
cargo build
cargo test
```

### Go procedure

```bash
nix develop    # devShell must have go, gcc (for CGO)
go build ./...
go test ./...
```

### C/C++ procedure

```bash
nix develop    # devShell with gcc, gnumake, pkg-config
./configure
make
```

## Universal fallback

```bash
nix shell nixpkgs#<package-name> --command <tool> <args>
```

Search: `nix search nixpkgs <keyword>`

## Writing scripts on NixOS

Always use `#!/usr/bin/env bash` (not `#!/bin/bash`),
`#!/usr/bin/env python3`, `#!/usr/bin/env node`.

## Writing CI pipelines

Target `ubuntu-latest` runners:

```yaml
- uses: cachix/install-nix-action@v27
  with:
    extra_nix_config: "experimental-features = nix-command flakes"
- run: nix develop --command make test
```
