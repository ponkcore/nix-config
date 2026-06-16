# Workflows

> Step-by-step recipes. When something is a routine repeatable
> operation, it lives here so it isn't reinvented every time.

## TL;DR

Routine: edit → `rebuild-test` → if green → `git commit` → `rebuild`.
Non-routine: read the relevant module's header comment and
`docs/architecture.md` first.

---

## 1. Make a code change

### Routine
```sh
$EDITOR /etc/nixos/<file>
sudo nixos-rebuild test --flake /etc/nixos#lecoo --show-trace 2>&1 | tail -40
git -C /etc/nixos add -A
git -C /etc/nixos commit -m "<type>(<scope>): <description>"
sudo nixos-rebuild switch --flake /etc/nixos#lecoo
```

Pre-commit hooks (alejandra/statix/deadnix/nil/gitleaks) run on
`git commit` and will fail noisily if anything's wrong. After
alejandra modifies files, re-stage with `git add -A` and retry.

If the change touches Hyprland or Waybar runtime state — for example
`home/desktop/sessions/hyprland/session.nix`,
`home/desktop/sessions/hyprland/waybar.nix`, or
`theme/waybar/default.nix` — restart Waybar after activation:

```sh
systemctl --user restart waybar.service
```

This prevents the `hyprland/workspaces` module from keeping stale IPC
state after a compositor reload; see
`lessons/0005-waybar-workspace-stale-after-hyprland-reload.md`.

Before a full `nixos-rebuild test` or `switch`, turn off Throne/TUN mode.
A controlled rebuild with Throne off kept Wi-Fi, route, DNS, and ping stable
for 166 consecutive samples; previous long-lived "internet down" incidents
occurred with `throne-tun` active. Re-enable Throne after the rebuild if
needed.

### Failure modes

| Symptom | Cause | Fix |
|---------|-------|-----|
| `nixos-rebuild` says "module not found" | typo in import path | check relative paths; `find /etc/nixos -name <basename>` |
| "option … does not exist" | option renamed in nixpkgs | `nix flake update` or check upstream changelog |
| pre-commit fails on alejandra | code wasn't formatted | run `alejandra .`, re-stage |
| pre-commit fails on statix | anti-pattern detected | follow the suggestion, or document with `# statix-disable: WXX` |
| pre-commit fails on deadnix | unused arg/binding | remove or prefix with `_` |
| pre-commit fails on nil | eval-time error (typo, unbound var) | read message, fix the .nix file |
| pre-commit fails on gitleaks | secret in staged diff | remove the secret, move to agenix, re-stage |
| HM activation aborts: "is in the way" | non-symlink file pre-existing | move it elsewhere or delete |

---

## 2. Add a new application

See `docs/handbook.md` §2 — full decision flow with examples.

---

## 3. Add or rotate a secret

### New secret
```sh
cd /etc/nixos/secrets

# 1. Add to secrets.nix:
#    "<name>.age".publicKeys = all;
#  (or a narrower subset if it should NOT decrypt on every host)

# 2. Encrypt it:
agenix -e <name>.age
# editor opens (interactive); type the plaintext, save, quit.
# the resulting <name>.age is binary, safe to commit.

# 3. Wire it into NixOS:
#    modules/nixos/secrets.nix:
#      age.secrets.<name> = {
#        file = ../../secrets/<name>.age;
#        owner = username;
#        mode  = "400";
#      };

# 4. Reference from consumer:
#    config.age.secrets.<name>.path  -> /run/agenix/<name>

# 5. Rebuild + commit
sudo nixos-rebuild switch --flake /etc/nixos#lecoo
git -C /etc/nixos add -A
git -C /etc/nixos commit -m "feat(secrets): add <name>"
```

### Rotate an existing secret (key compromised)
```sh
cd /etc/nixos/secrets
agenix -e <name>.age
# replace value, save, quit
sudo nixos-rebuild switch --flake /etc/nixos#lecoo
git -C /etc/nixos add -A
git -C /etc/nixos commit -m "fix(secrets): rotate <name>"
```

### Re-encrypt for a new authorised key
```sh
# Edit secrets/secrets.nix to add the new public key,
# then re-encrypt every file with the new recipient set:
cd /etc/nixos/secrets
agenix -r
git -C /etc/nixos add -A
git -C /etc/nixos commit -m "chore(secrets): re-encrypt for <new key>"
```

---

## 4. Add a new host

See `docs/handbook.md` §5 — installation steps from boot USB to
working system in ~10 minutes.

After install, on the dev machine:
```sh
# Authorise the new host's SSH host key in secrets/secrets.nix,
# then re-encrypt:
cd /etc/nixos/secrets && agenix -r
git -C /etc/nixos commit -am "feat(secrets): authorise <name> host"
git -C /etc/nixos push
```

The new host pulls the latest commit and re-runs `nixos-rebuild switch`
to pick up the re-encrypted secrets.

---

## 5. Update flake inputs

```sh
# Update everything:
nix flake update

# Update a specific input:
nix flake lock --update-input nixpkgs

# Apply:
sudo nixos-rebuild switch --flake /etc/nixos#lecoo

# Commit:
git -C /etc/nixos commit -am "chore(flake): update flake.lock"
```

---

## 6. Roll back a broken change

### Without rebooting
```sh
sudo nixos-rebuild switch --flake /etc/nixos#lecoo --rollback
```

### Via boot menu
Reboot, pick a previous generation. Up to 7 are kept.

### Inspect what changed between generations
```sh
nix store diff-closures /run/booted-system /run/current-system
```

---

## 7. Free disk space

```sh
gc                                                       # fish alias
sudo nix-collect-garbage --delete-older-than 14d         # explicit
sudo nix store optimise                                   # hard-link dedup
journalctl --vacuum-size=200M                            # trim journal
```

The flake also runs weekly GC and daily optimise via systemd timers,
so this is for "I need space NOW" cases.

---

## 8. Investigate a regression

```sh
# 1. Boot timing
systemd-analyze blame | head -20
systemd-analyze critical-chain

# 2. Failed services
systemctl --failed
systemctl --user --failed

# 3. Recent journal — system + user
journalctl -p warning -b --no-pager
journalctl --user -p warning -b --no-pager

# 4. Compare current vs previous generation
nix store diff-closures /nix/var/nix/profiles/system-{N-1}-link \
                         /nix/var/nix/profiles/system-N-link
```

---

## 9. Pair a new device for sync

See `docs/handbook.md` §3 Layer 3 — Syncthing first-time pairing.

Short version:
1. Open `http://127.0.0.1:8384` on laptop.
2. Read the laptop's Device ID from Settings → "This Device".
3. Add as remote on the other device.
4. Accept on laptop side.
5. Share the relevant folder (e.g. `~/Documents/secrets/`).
6. Accept the folder on the partner.

---

## 10. Recover after a force-shutdown / power loss

NixOS ext4 with `commit=60` may lose up to a minute of writes on hard
power-loss. The system itself is fine; user data may have a few seconds
of dirty state lost.

```sh
# 1. Boot. Filesystem auto-mounts; journald replays.
# 2. Check for filesystem inconsistencies:
sudo dmesg | grep -iE 'ext4|EXT4'
# 3. Check failed units:
systemctl --failed
# 4. If a service is crashing on stale state, isolate:
sudo systemctl reset-failed <unit>
sudo systemctl restart <unit>
```

If `/boot` (vfat) needs fsck, the kernel will say so — boot via USB,
`fsck.vfat -a /dev/nvme0n1p1`.

---

## 11. Investigate "is anything leaking"

```sh
# Memory leaks in user processes
ps aux --sort=-rss | head -15

# CPU
ps aux --sort=-%cpu | head -15

# Open files / sockets
sudo lsof -nP +c0 | wc -l
ss -tnlp

# Specific suspect process
pgrep -af <name> | wc -l

# Donut-proxy reaper running OK?
systemctl --user status donut-proxy-reaper.timer
journalctl --user -u donut-proxy-reaper.service --since '1 hour ago'
```
