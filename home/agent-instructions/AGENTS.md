# NixOS 26.05 — Universal Agent Rules

You are operating on **NixOS 26.05**. This is NOT a standard Linux
distribution. Standard package management commands DO NOT WORK here.
Read this file fully before taking any action that involves
installing software, running build tools, or executing binaries.

## What NOT to do (and why)

| Command | Why it fails | What to do instead |
|---------|-------------|-------------------|
| `pip install <pkg>` | PEP 668: Python is in immutable /nix/store | Create venv first (see Python section) |
| `pip install --user <pkg>` | No writable user site-packages on NixOS | Create venv first |
| `npm install -g <pkg>` | No writable global npm prefix | `npx <pkg>` or `nix shell nixpkgs#nodePackages.<pkg>` |
| `yarn global add <pkg>` | Same as npm -g | `nix shell nixpkgs#nodePackages.<pkg>` |
| `pnpm add -g <pkg>` | Same as npm -g | `nix shell nixpkgs#nodePackages.<pkg>` |
| `apt install <pkg>` | apt does not exist on NixOS | `nix shell nixpkgs#<pkg>` |
| `brew install <pkg>` | brew does not exist on NixOS | `nix shell nixpkgs#<pkg>` |
| `pacman -S <pkg>` | pacman does not exist on NixOS | `nix shell nixpkgs#<pkg>` |
| `nix-env -i <pkg>` | Imperative, breaks reproducibility | Add to flake.nix devShell |
| `./downloaded-binary` | ELF interpreter missing (nix-ld enabled — should work) | See FHS Binary section if it fails |
| `#!/bin/bash` in scripts | /bin/bash does not exist on NixOS | Use `#!/usr/bin/env bash` |

## Entering the development environment

Before running ANY build, install, or test command:

1. Check if `flake.nix` exists in the project root.
   - If yes AND `.envrc` exists: run `direnv allow` (one-time per
     project), then commands work automatically.
   - If yes but no `.envrc`: run `nix develop` to enter the devShell.
     All commands work inside.
   - If neither exists: use `nix shell nixpkgs#<package>` for
     individual tools.

2. Check if `.envrc` exists without `flake.nix`: run `direnv allow`.

3. Never assume tools are in PATH without checking. Run
   `which gcc` / `which python` / `which node` first.

## Ad-hoc tool installation

When you need a tool that is not in the devShell:

```sh
nix shell nixpkgs#<package-name> --command <tool> <args>
```

Common mappings:

- gcc → `nixpkgs#gcc`
- make → `nixpkgs#gnumake`
- python3 → `nixpkgs#python3`
- node → `nixpkgs#nodejs_22`
- curl → `nixpkgs#curl`
- jq → `nixpkgs#jq`
- git → `nixpkgs#git`

## FHS binary procedure

When a downloaded binary fails with "No such file or directory"
despite the file existing and being executable:

```sh
# Option 1: nix-ld is enabled system-wide — the binary should just
# work. If it does not, proceed to Option 2.

# Option 2: steam-run (no config change needed)
steam-run ./binary

# Option 3: patchelf (permanent fix for scripted use)
patchelf --set-interpreter "$(patchelf --print-interpreter "$(which ls)")" ./binary
./binary
```

## Python procedure

```sh
# Step 1: Enter devShell (must have python in buildInputs)
nix develop
# OR: nix shell nixpkgs#python3

# Step 2: Create venv (do this once per project)
python -m venv .venv

# Step 3: Activate
source .venv/bin/activate

# Step 4: Now pip works normally
pip install -r requirements.txt
pip install <pkg>
pip install -e .
```

Never run pip outside an activated venv on NixOS.

## Node.js procedure

```sh
# Enter devShell first
nix develop

# Local installs work fine
npm install
npm ci

# For global tools, use npx instead
npx <tool>

# Or nix shell for repeated use
nix shell nixpkgs#nodePackages.<pkg>
```

## Rust procedure

```sh
# Enter devShell (must have cargo, rustc, gcc)
nix develop
cargo build
cargo test
```

If you see `error: linker 'cc' not found`, the devShell is missing
`pkgs.gcc`.

## Go procedure

```sh
# Enter devShell (must have go, gcc for CGO)
nix develop
go build ./...
go test ./...
```

## C/C++ procedure

```sh
# Enter devShell with gcc, gnumake, pkg-config
nix develop
./configure
make
```

## Nix development environments (flake.nix)

If the project has no `flake.nix` and you need a devShell:

- For **standard stacks** (Python, Node, Rust, Go): copy the
  relevant template from `~/.local/share/nixos-templates/` to the
  project root as `flake.nix`, then modify it. Available templates:
  `python-flake.nix`, `node-flake.nix`, `rust-flake.nix`,
  `go-flake.nix`, `polyglot-flake.nix`. Also copy `envrc` to
  `.envrc`. Never edit the template path directly — it is a
  read-only Nix store symlink.
- For **non-standard or polyglot stacks**: write `flake.nix` from
  scratch using `pkgs.mkShell { buildInputs = [...]; }`. Do not
  copy a template and strip it down — write only what is needed.
- After creating `flake.nix`, create `.envrc` with `use flake` and
  run `direnv allow`.

## Writing scripts

Always use:
- `#!/usr/bin/env bash` (not `#!/bin/bash`)
- `#!/usr/bin/env python3` (not `#!/usr/bin/python3`)
- `#!/usr/bin/env node` (not `#!/usr/bin/node`)

## Writing CI pipelines

Use `ubuntu-latest` runners. The NixOS host is irrelevant to CI
YAML. To use the project's devShell in CI:

```yaml
- uses: cachix/install-nix-action@v27
  with:
    extra_nix_config: "experimental-features = nix-command flakes"
- run: nix develop --command make test
```

## Deployment target

NixOS-built binaries have ELF interpreter and rpath pointing to
`/nix/store/` paths that do not exist on Ubuntu/standard Linux.
For deployment:
- Build inside a Docker container with a standard base image, OR
- Use `pkgsStatic` for static linking, OR
- Use `nix bundle` for self-contained packages.

## When in doubt

```sh
nix shell nixpkgs#<package-name>
```

Search for package names: `nix search nixpkgs <keyword>`
