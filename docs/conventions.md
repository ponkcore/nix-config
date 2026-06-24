# Conventions

> Code-style and review rules for this repository. All hooks listed
> here are enforced via `.pre-commit-config.yaml` — failure blocks
> commits.

## TL;DR

Five commands — alejandra, statix, deadnix, nil, gitleaks — must
pass before any commit. Conventional Commits, lowercase imperative,
≤72 chars. `nixos-rebuild test` must pass before `switch`.
Never `--no-verify`.

---

## 1. Declarative purity

Everything is managed through Nix. There is no escape hatch.

| DO | DO NOT |
|----|--------|
| `modules/nixos/packages.nix` or `home/<app>.nix` | `nix-env -iA`, `apt`, `pip install` |
| `pkgs/<name>/default.nix` + overlay | `cp binary /usr/local/bin` |
| `home.file` / `xdg.configFile` | edit `~/.config/*` directly (HM overwrites) |
| `systemd.services.*` in a module | `systemctl enable …` |
| `home.activation` for runtime templating | hardcode secrets in `.nix` files |

## 2. Repository layout

| Directory | Purpose |
|-----------|---------|
| `flake.nix` / `flake.lock` | inputs, outputs, host registrations |
| `lib/` | helpers consumed by `flake.nix` (mkHost, palette) |
| `hosts/<name>/` | one host per directory, composes universal+hardware modules |
| `modules/nixos/` | universal NixOS layer; `default.nix` aggregates leaves |
| `modules/nixos/desktop/` | Wayland desktop sub-tree |
| `modules/hardware/` | opt-in profiles (cpu/, gpu/, form-factor/, boot/) |
| `home/` | Home Manager modules, one app or concern per file |
| `theme/` | desktop theme bundle, palette consumers |
| `pkgs/<name>/default.nix` | local package derivations; registered in `pkgs/default.nix` |
| `secrets/` | agenix-encrypted secrets + `secrets.nix` authorisation map |
| `docs/` | architecture, handbook, conventions, decisions, changelogs |
| `assets/` | wallpapers, screenshots |

### Naming
- Lowercase, hyphen-separated for multi-word: `lid-monitor.nix`.
- `default.nix` only for aggregator/composition files.
- One concern per file. If a file describes more than one thing,
  split it.

### Import discipline
- `flake.nix` imports nothing — it builds via `mkHost` from `lib/`.
- `lib/mkHost.nix` imports `modules/nixos`, `home/`, `pkgs/`.
- `hosts/<name>/default.nix` imports `hardware-configuration.nix`,
  the relevant `modules/hardware/*` profiles, and host-specific files.
- `modules/nixos/default.nix` imports leaves under `modules/nixos/`.
- `home/default.nix` imports leaves under `home/` and `../theme`.
- `theme/default.nix` imports leaves under `theme/`.
- Cross-layer imports (e.g. `home/` reaching into `modules/`) are
  forbidden. Shared data flows through `_module.args` or `lib/`.

## 3. Nix code style

### Required tools (run automatically by pre-commit)
| Tool | Purpose |
|------|---------|
| `alejandra` | format every `.nix` file |
| `statix check --config statix.toml` | lint anti-patterns |
| `deadnix --no-lambda-pattern-names --fail` | catch dead bindings |
| `nil diagnostics` | eval-time errors (Nix LSP, single-file mode) |
| `gitleaks git --pre-commit --staged` | secret scan on the index |

### Patterns

```nix
# Module function signature — ONLY arguments the body actually uses.
{
  pkgs,
  lib,
  ...
}: {
  # body
}

# Empty pattern — use `_:`, never `({...}: ...)`.
_: {
  body = true;
}

# Local bindings via `let ... in`, not nested `with`.
let
  cfg = config.services.foo;
in {
  # body
}

# `with pkgs;` ONLY inside list literals.
home.packages = with pkgs; [
  ripgrep
  fd
];

# Boolean options: explicit, never bare.
programs.fish.enable = true;   # right
programs.fish.enable;          # wrong
```

### Best practices
- Preserve existing comments; don't add or remove without reason.
- Match the conventions of neighbouring files before introducing new
  patterns.
- Use `lib.mkIf` for conditional config blocks, not Nix `if … then …`.
- Use `lib.mkDefault` for values downstream might override.
- Use `lib.mkForce` only when overriding upstream defaults — sparingly.
- Header comment at the top of every file: 3–5 lines stating the
  module's purpose, scope, and any non-obvious decision.

## 4. Git conventions

### Branches
- `main` is the only long-lived branch.
- No feature branches for solo work — atomic conventional commits suffice.
- If working on a risky refactor, use a short-lived branch and merge
  fast-forward when done.

### Commit format
```
<type>(<scope>): <short description>
```

| Type | Use when |
|------|----------|
| `feat` | new module, package, capability |
| `fix` | bug or rebuild error resolution |
| `refactor` | restructuring without behaviour change |
| `style` | whitespace / palette / cosmetic |
| `docs` | docs-only changes |
| `chore` | maintenance (GC, lock updates, version bumps) |

**Scope:** module name without `.nix`, or `flake`, `secrets`, `host`, `hardware`.

**Rules:**
- Lowercase, imperative mood ("add X", not "added X").
- Max 72 characters first line.
- Body optional — use to explain *why*, not *what*.
- No merge commits — keep linear history.

**Examples:**
```
feat(secrets): adopt agenix for encrypted secrets in repo
fix(virtualisation): mask libvirtd 11.7.0 cosmetic exit-1 on idle shutdown
refactor: split flake into universal/hardware/host layers
chore(flake): update flake.lock
```

## 5. Verification before commit

```sh
# 1. Format
alejandra .

# 2. Lint
statix check --config statix.toml

# 3. Dead code
deadnix --no-lambda-pattern-names --fail

# 4. Diagnostics (eval-time errors)
nil diagnostics <changed-file.nix>

# 5. Secret scan (staged index only)
gitleaks git --pre-commit --staged --no-banner --redact

# 6. Build test (no boot entry)
sudo nixos-rebuild test --flake /etc/nixos#lecoo --show-trace 2>&1 | tail -80

# 7. Commit (pre-commit hooks re-run 1-5 automatically)
git add -A
git commit -m "<type>(<scope>): <description>"

# 8. Apply
sudo nixos-rebuild switch --flake /etc/nixos#lecoo --show-trace 2>&1 | tail -80
```

## 6. Documentation

When you change behaviour:

- User-visible? Update `docs/handbook.md`.
- Architectural shift? Update `docs/architecture.md`.
- Workflow, command, invariant, repository layout, agent contract, or
  runtime wiring changed? Update `README.md` and/or `AGENTS.md` in the
  same change set before pushing.
- Module-level reasoning? Add or extend the header comment of the
  relevant `.nix` file (3-5 lines explaining purpose, scope, and any
  non-obvious decision).

## 7. Things that must never happen

1. `nix-env -i` anything.
2. Manual edits to HM-managed files.
3. `git push` without reviewing for secrets (`git diff --stat`).
4. `git reset --hard` or `git rebase -i` without explicit user approval.
5. Changing `system.stateVersion`.
6. Disabling pre-commit hooks (`--no-verify`).
7. `allowUnfree` per-package — global only.
8. Imperative `systemctl enable/disable` for declarative units.
9. Writing to `/etc/` directly outside the flake.
10. Committing plaintext secrets.
11. Force-pushing to `main`.
