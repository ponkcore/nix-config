# Handbook

> User manual for ponkcore's NixOS system.
> Read top to bottom once, then jump to sections by need.

## TL;DR

This is a flake-managed NixOS system. The whole machine — kernel
parameters, every installed application, every user dotfile, every
encrypted secret — is described in `/etc/nixos/`. Changes are atomic,
reversible, version-controlled.

Three commands cover 95% of daily life:

```fish
rebuild           # apply changes (nixos-rebuild switch)
rebuild-test      # try changes without committing to a boot entry
gc                # delete old generations
```

If something breaks: pick the previous generation in the boot menu and
keep going. Nothing is permanent.

---

## 1. Daily operations

### Apply a change you just made
```fish
rebuild
```

Runs `sudo nixos-rebuild switch --flake /etc/nixos#lecoo` piped through
`nom` (nix-output-monitor) for readable progress. Adds a new boot menu
entry, activates the new generation immediately.

### Try without committing
```fish
rebuild-test
```

Activates the new configuration but DOES NOT add a boot menu entry.
Reboot reverts to the previous generation. Use this to iterate.

### Roll back without rebooting
```fish
sudo nixos-rebuild switch --rollback
```

Activates the previous generation. The current-broken generation is
still in the boot menu in case you change your mind.

### Roll back via boot menu
Reboot, pick a previous generation from the systemd-boot list. Last
seven generations are kept (configurationLimit=7).

### Garbage-collect old generations
```fish
gc
```

Wraps `nix-collect-garbage` and HM's GC for the user. The flake also GCs
weekly automatically (older than 14 days), so this is for "free up disk
NOW" situations.

### Update flake inputs
```fish
nix flake update                          # update everything
nix flake lock --update-input nixpkgs     # update one
```

Then `rebuild`. Commit the resulting `flake.lock` with
`chore(flake): update flake.lock`.

### Where to look when something is wrong

| Problem | Place to look |
|---------|---------------|
| Service died | `journalctl -u <unit> -b` |
| Kernel issue | `sudo dmesg --level=err,warn` |
| Recent boot trace | `journalctl -b --no-pager` |
| Slow boot | `systemd-analyze blame`, `systemd-analyze critical-chain` |
| Failed units | `systemctl --failed` and `systemctl --user --failed` |
| User session messages | `journalctl --user -b` |
| Power management state | `powerprofilesctl get` / `cat /sys/firmware/acpi/platform_profile` |

---

## 2. Installing software (the right way)

The system is declarative — nothing gets installed by typing `pip
install` or `nix-env -i`. Always go through the flake.

### Decision flow

```
Want to install <name>?
        │
        ▼
1. Is it in nixpkgs?
        │
   nix search nixpkgs#<name>
        │
        ├── Yes → Add via flake (steps 2-3)
        │
        └── No  → check NUR / write a derivation (step 4)

2. System-wide CLI tool?
        │
   Add to modules/nixos/packages.nix
        │
        ▼

3. Per-user app?
        │
   Has HM module?  →  Yes → home/<name>.nix → programs.<name>.enable = true
                  │
                  └ No  → add pkgs.<name> to home.packages in a relevant home/*.nix

4. Not in nixpkgs?
        │
        ├── In NUR?  →  pkgs.nur.repos.<author>.<name> in home.packages
        │
        ├── AppImage / binary release?  →  pkgs/<name>/default.nix
        │                                  + register in pkgs/default.nix overlay
        │
        └── Custom build?  →  pkgs/<name>/default.nix (callPackage / buildGoModule etc.)
```

After any change: `rebuild-test`, then `rebuild`.

### Anti-patterns (NEVER do these)

| Tempting | Why wrong | Right thing |
|----------|-----------|-------------|
| `nix-env -iA nixpkgs.<name>` | not declarative, escapes flake | edit `packages.nix` or `home/<name>.nix` |
| `pip install --user X` | breaks Python sandbox, eventually conflicts | `python312.withPackages` in `home.packages` |
| `npm install -g X` | leaks into `~/.npm`, hard to track | `nodePackages.X` or pin via flake |
| `cargo install X` | unmanaged binary in `~/.cargo/bin` | derive from nixpkgs or write a package |
| `curl … | sh` | sets fire to the system | wrap as a derivation in `pkgs/<name>/` |
| Editing `~/.config/<app>/*` directly | HM overwrites it on next rebuild | edit `home/<app>.nix` |
| Editing `/etc/<file>` directly | NixOS overwrites it on next rebuild | find the right module |

### Examples (real ones from this repo)

System CLI tool (`fd`, `ripgrep`, `pamixer`):
```nix
# modules/nixos/packages.nix
environment.systemPackages = with pkgs; [
  ...
  ripgrep
  fd
  pamixer
];
```

Per-user app with HM module (Firefox):
```nix
# home/firefox.nix
programs.firefox = {
  enable = true;
  profiles.default = { ... };
};
```

Per-user package without HM module (KeePassDX is mobile so n/a; example
for ayugram-desktop):
```nix
# home/default.nix
home.packages = with pkgs; [
  ayugram-desktop
];
```

NUR package (uBlock Origin):
```nix
# home/firefox.nix
programs.firefox.profiles.default.extensions = with pkgs.nur.repos.rycee.firefox-addons; [
  ublock-origin
  sidebery
];
```

AppImage / binary (donutbrowser):
```nix
# pkgs/donutbrowser/default.nix    — derivation
# pkgs/default.nix                  — overlay registration
# home/donutbrowser.nix             — home.packages = [ pkgs.donutbrowser ]
```

---

## 3. Secrets and passwords

Three layers, three different tools. Don't mix them up.

### Layer 1 — System API keys (agenix)

For things consumed by NixOS / Home Manager activation: provider keys,
service tokens, deploy keys. Stored encrypted in `secrets/*.age`,
decrypted at activation by the host's SSH host key.

**Add a new secret:**
```fish
cd /etc/nixos/secrets
# add the new file's name to secrets.nix with appropriate publicKeys
agenix -e my-new-secret.age
# editor opens; type something like:
#   MY_API_KEY=sk-...
# save & quit
```

Then in a NixOS module:
```nix
age.secrets.my-new-secret = {
  file = ../../secrets/my-new-secret.age;
  owner = username;
  mode = "400";
};
# consumer references config.age.secrets.my-new-secret.path
# default location: /run/agenix/my-new-secret
```

`rebuild` and the secret lands at `/run/agenix/my-new-secret`.

**Edit an existing secret:**
```fish
cd /etc/nixos/secrets
agenix -e tokens.age
```

**Authorise a new editor or new host:**
1. Get their `ssh-ed25519 ...` public key
   (host: `ssh-keyscan -t ed25519 <host>` or
    `cat /etc/ssh/ssh_host_ed25519_key.pub`;
    user: `cat ~/.ssh/id_ed25519.pub`).
2. Add to `secrets/secrets.nix` under the right `let` binding and
   `publicKeys` lists.
3. `cd secrets && agenix -r` re-encrypts everything for the new key set.

### Layer 2 — Web / banking / 2FA / notes (KeePassXC)

For everything human-typed: web logins, bank cards, server SSH passphrases,
2FA TOTP codes, recovery hints, scanned passport photos.

**First-time setup:**
1. Run `keepassxc` (rofi or the tray).
2. Create a new database at `~/Documents/secrets/vault.kdbx`.
3. Pick a STRONG master passphrase. This is the one you must never lose.
4. KeePassXC → Tools → Settings → Browser Integration → enable + tick
   the browser(s) you want.
5. Install the `KeePassXC-Browser` extension in Firefox / Chromium.
6. Click "Connect" in the extension; KeePassXC pops a connection prompt;
   accept and name the association.

**Daily use:**
- Tray icon → unlock with master passphrase.
- Browser auto-fill: Ctrl+Shift+B in any input field, or right-click →
  KeePassXC autofill.
- Adds, edits, search via the GUI. Tag everything for fast retrieval.

**Lock/unlock:**
- Ctrl+L locks immediately.
- Auto-locks after 5 minutes idle (configurable in settings).

### Layer 3 — Cross-device sync (Syncthing)

For the .kdbx file itself, plus `~/Documents`, `~/Pictures` etc.

**First-time pairing with another device:**

1. On the laptop: open `http://127.0.0.1:8384`. The web UI is bound to
   localhost; visit it from the laptop's own browser.
2. Note the laptop's Device ID (Settings → "This Device").
3. On the partner device (Android: Syncthing-Fork from F-Droid; another
   NixOS: same `services.syncthing` module), enter the laptop's Device ID
   as a remote device.
4. Laptop side prompts to accept the new device — accept.
5. Define a folder to share. For the password vault:
   - Path on laptop: `~/Documents/secrets/`
   - Folder ID: `secrets-vault`
   - Share with: the Android device.
6. Android side prompts to accept the folder — accept and pick a local
   path. KeePassDX opens the .kdbx from that path.

**What gets synced** (default plan):
- `~/Documents/secrets/` → laptop ↔ Android ↔ (future devices)
  Holds `vault.kdbx`. NEVER share publicly.
- `~/Documents/` → laptop ↔ devices you trust (your own).
- Bigger folders (Pictures, code) — add only if Syncthing storage on
  the partner allows.

**Conflict handling:** Syncthing renames the loser to `<file>.sync-conflict-…`
when two devices change the same file simultaneously. Investigate manually.

### Layer ∞ — Emergency recovery

The master passphrase to your KeePass vault is the keys to the kingdom.
Lose it, lose everything.

Where it lives:
- **In your head** (primary).
- **Paper, written by hand, in a safe / bank box** (secondary).
- **Encrypted USB stored elsewhere** (tertiary).

NEVER in plaintext email/notes/Telegram/Google Keep. NEVER reuse it
anywhere else.

---

## 4. Keeping the system in pristine condition

### Dirty git tree?
```
git -C /etc/nixos status
```
Empty output is the goal. Uncommitted changes between `rebuild`s are
fine while iterating, but never reboot with uncommitted work — recovery
gets harder.

### Pre-commit hooks failed
```
alejandra .                                 # auto-format, may modify files
statix check --config statix.toml           # lint
deadnix --no-lambda-pattern-names --fail    # detect dead code
nil diagnostics <files>                     # eval-time errors
gitleaks git --pre-commit --staged          # secret scan
```

After alejandra modifies files, re-stage with `git add -A` and commit
again. NEVER `--no-verify`.

### Disk filling up
```fish
gc                                                 # user shortcut
sudo nix-collect-garbage --delete-older-than 14d   # explicit
sudo nix store optimise                            # hard-link dedup
```

### Boot menu cluttered
`nix.gc.options = "--delete-older-than 14d"` is the source of truth.
Adjust in `modules/nixos/nix.nix` if you want a different window.
`boot.loader.systemd-boot.configurationLimit = 7` caps the boot menu.

### Periodic timers (already running)

### CloakBrowser (stealth Chromium, C++ patches)

CloakBrowser is a Chromium fork with 58 source-level C++ patches
covering canvas, WebGL, audio, fonts, GPU, screen, WebRTC,
navigator.deviceMemory, navigator.webdriver, plugins, window.chrome,
TLS fingerprint, and CDP detection. It is the primary anti-detect
browser. fingerprint-chromium remains as a secondary option.

```fish
cb list                          # list profiles
cb create                        # rofi: name → platform → random seed
cb launch shop-01                # launch by name
cb validate shop-01              # open fingerprint test sites
cb delete shop-01                # remove profile + data
```

Or use the rofi launcher (Super+D → "CloakBrowser"):
the picker shows all profiles plus a "➕ Create profile..." option.

Profile definitions (seed, platform, timezone, colorScheme, etc.)
are stored in:

```text
~/.config/cloakbrowser/profiles.json
```

Mutable browser data (cookies, cache, extensions) lives in:

```text
~/.local/share/cloakbrowser/<profile>/
```

### fingerprint-chromium spike

The experimental Donut replacement candidate is installed with an
imperative profile manager. Donut remains available while this is
validated. Profiles are created/deleted at runtime — no rebuild needed.

```fish
fp list                          # list profiles
fp create                        # rofi: name → platform → random seed
fp launch shop-01                # launch by name
fp validate shop-01              # open fingerprint test sites
fp delete shop-01                # remove profile + data
```

Or use the rofi launcher (Super+D → "Fingerprint Chromium"):
the picker shows all profiles plus a "➕ Create profile..." option.

Profile definitions (seed, platform, timezone, colorScheme, etc.)
are stored in:

```text
~/.config/fingerprint-chromium/profiles.json
```

Each profile includes a `colorScheme` field (`"light"` or `"dark"`,
default `"light"`) that controls the `prefers-color-scheme` CSS
media query. The launcher also spoofs `prefers-reduced-motion`,
`screen.width`, `screen.height`, `window.devicePixelRatio`, and
`navigator.hardwareConcurrency` — all derived from the profile seed
and platform, using fingerprint-chromium's own flags
(`--fingerprint-screen-width/height`, `--fingerprint-device-scale-
factor`, `--fingerprint-hardware-concurrency`) plus Chromium's
`--force-prefers-no-reduced-motion` and `--blink-settings`. These
override JS-visible values without affecting actual rendering.
Known unspoofed leaks: `navigator.deviceMemory` (no flag, hardcoded
in V8), WebGL unmasked renderer (fingerprint-chromium's spoof is
incomplete on some test sites).

Mutable browser data (cookies, cache, extensions) lives in:

```text
~/.local/share/fingerprint-chromium/<profile>/
```

The launcher auto-detects the VPN routing mode in priority order:

1. **TUN transparent proxy** (preferred): when Throne's `throne-tun`
   interface is active, sing-box's nftables rules (`table inet
   sing-box`) redirect TCP to a local tproxy port and fwmark-mark
   UDP for TUN table routing. The browser is unaware of the VPN —
   no proxy fingerprint, QUIC works natively.
2. **SOCKS5 fallback**: when TUN is inactive, the launcher falls
   back to `--proxy-server=socks5://127.0.0.1:2080` with
   `--disable-quic`. This is proxy-aware (worse for anti-detect) but
   prevents IP leaks when TUN is unavailable.
3. **Warning**: if neither TUN nor SOCKS is detected, the browser
   launches with a stderr warning — traffic will use the real IP.

DoH (Cloudflare 1.1.1.1, "secure" mode) is set via Local State as
defense-in-depth against DNS-level geolocation leaks.

Explicit overrides: `FINGERPRINT_CHROMIUM_PROXY_SERVER` (force a
specific proxy), `FINGERPRINT_CHROMIUM_NO_PROXY=1` (connect directly),
`FINGERPRINT_CHROMIUM_SOCKS_PORT` (non-default SOCKS port),
`FINGERPRINT_CHROMIUM_PROXY_ENV_FILE` (runtime secret file).

| Timer | What | When |
|-------|------|------|
| `nix-gc.timer` | weekly GC | Mon 00:00 |
| `nix-optimise.timer` | weekly hard-link dedup | daily 03:45 |
| `fstrim.timer` | SSD TRIM | monthly |
| `donut-proxy-reaper.timer` (user) | kill stale donut-proxy workers | every 15 min |
| `hm-backup-cleanup.timer` (user) | delete old `.hm-backup` files | weekly |

---

## 5. Moving to new hardware / new device

The whole point of this flake is portability. Adding a host is a
short, repeatable ritual.

### Steps

1. Boot the target machine off a NixOS 25.11 installer USB.

2. Partition + filesystems (will be replaced by `disko.nix` later;
   for now, manual):
   ```sh
   # Examples for an ext4 + EFI layout (no encryption yet)
   sudo parted /dev/nvme0n1 -- mklabel gpt
   sudo parted /dev/nvme0n1 -- mkpart ESP fat32 1MiB 1GiB
   sudo parted /dev/nvme0n1 -- set 1 esp on
   sudo parted /dev/nvme0n1 -- mkpart primary ext4 1GiB 100%
   sudo mkfs.fat -F32 /dev/nvme0n1p1
   sudo mkfs.ext4 -L nixos /dev/nvme0n1p2
   sudo mount /dev/nvme0n1p2 /mnt
   sudo mkdir -p /mnt/boot && sudo mount /dev/nvme0n1p1 /mnt/boot
   ```

3. Generate hardware config:
   ```sh
   sudo nixos-generate-config --root /mnt
   ```

4. Clone the flake:
   ```sh
   sudo nix-shell -p git
   sudo git clone https://github.com/ponkcore/nix-config /mnt/etc/nixos
   ```

5. Make a host directory:
   ```sh
   sudo mkdir /mnt/etc/nixos/hosts/<name>
   sudo cp /mnt/etc/nixos/hardware-configuration.nix /mnt/etc/nixos/hosts/<name>/
   ```

6. Create `/mnt/etc/nixos/hosts/<name>/default.nix`:
   ```nix
   {...}: {
     imports = [
       ./hardware-configuration.nix
       # Pick the right hardware-class profiles:
       ../../modules/hardware/cpu/amd.nix
       ../../modules/hardware/gpu/amd.nix
       ../../modules/hardware/form-factor/laptop.nix
     ];
     system.stateVersion = "25.11";
   }
   ```

7. Register in `/mnt/etc/nixos/flake.nix`:
   ```nix
   nixosConfigurations.<name> = mkHost {
     hostname       = "<name>";
     username       = "oonishi";
     system         = "x86_64-linux";
     # Wayland sessions installed on this host. Single entry →
     # defaultSession is inferred. List more to make several
     # selectable at the greeter (you'll need defaultSession then).
     # Headless / server hosts: omit `desktops` entirely.
     desktops       = [ "hyprland" ];
     # defaultSession = "hyprland";  # required only when len > 1
     modules        = [./hosts/<name>];
   };
   ```

8. The new host needs to decrypt secrets. Add its SSH host pubkey
   to `secrets/secrets.nix` and re-encrypt:
   ```sh
   # On the new host (after first boot):
   sudo cat /etc/ssh/ssh_host_ed25519_key.pub
   # Paste into secrets/secrets.nix on your dev machine.
   cd secrets && agenix -r
   git commit -am "feat(secrets): authorise <name> host"
   git push
   ```

9. Install:
   ```sh
   sudo nixos-install --flake /mnt/etc/nixos#<name>
   ```

10. Reboot, log in, sync KeePass + Syncthing. The new device is fully
    yours in ~10 minutes.

---

## 6. Adding a desktop session

The desktop layer is pluggable along its own axis. Each host's
`desktops` list (set in `flake.nix` via `mkHost`) decides which
Wayland sessions get installed. Adding a new session — niri, GNOME,
Sway, river, anything — is a folder-scale change with no edits to
existing sessions.

### Steps (e.g. adding niri)

1. **System enable** — create
   `modules/nixos/desktop/sessions/niri.nix`:
   ```nix
   { pkgs, ... }: {
     programs.niri.enable = true;
     environment.sessionVariables = {
       XDG_CURRENT_DESKTOP = "niri";
       XDG_SESSION_TYPE = "wayland";
       NIXOS_OZONE_WL = "1";
       MOZ_ENABLE_WAYLAND = "1";
       GDK_BACKEND = "wayland";
       QT_QPA_PLATFORM = "wayland;xcb";
     };
     # niri has no dedicated portal yet; xdg-desktop-portal-gnome
     # is the recommended fallback for screen-share / file picker.
     xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gnome ];
   }
   ```

2. **User config** — create
   `home/desktop/sessions/niri/{default,session,lock,idle,paper}.nix`.
   `default.nix` is just an `imports` aggregator; `session.nix`
   holds the `programs.niri` config (KDL); `lock.nix` /
   `idle.nix` / `paper.nix` use `swaylock` / `swayidle` /
   `swaybg` since niri does not ship its own.

3. **Theming (optional)** — if niri needs gruvbox-aware tweaks
   (border colors, gaps, shadows), add
   `theme/sessions/niri.nix` and import it from `theme/default.nix`
   guarded by `lib.mkIf (builtins.elem "niri" desktops)`.
   Compositor-agnostic UI (waybar, mako, rofi, ghostty) is
   shared — no edits there.

4. **Wire the dispatchers** — uncomment the matching line in
   `modules/nixos/desktop/default.nix` and
   `home/desktop/default.nix`. The dispatchers already know to
   look for `./sessions/niri.nix` and `./sessions/niri/`.

5. **Activate on a host** — extend `desktops` and pin
   `defaultSession` in `flake.nix`:
   ```nix
   lecoo = mkHost {
     hostname       = "lecoo";
     # ...
     desktops       = [ "hyprland" "niri" ];
     defaultSession = "hyprland";
     modules        = [./hosts/lecoo];
   };
   ```

6. **Build + verify** — `nix flake check && rebuild-test`.
   At login, the greeter (greetd + nwg-hello) shows both sessions
   in its dropdown; select "niri" once to try it.

### Notes

- **GNOME is special.** It replaces greetd with gdm
  automatically (the dispatcher in
  `modules/nixos/desktop/default.nix` selects `greeter/gdm.nix`
  whenever `gnome ∈ desktops`). Mixing GNOME with
  Hyprland on the same host is supported; gdm offers all
  sessions in its session menu.
- **Headless hosts** simply pass `desktops = []` (or omit the
  argument) — the desktop layer becomes a no-op.
- **Removing a session** is the inverse: drop it from
  `desktops`, then optionally delete the session files. The
  dispatcher tolerates the files lingering (they are only
  imported when listed).

---

## 7. Anti-patterns (the canonical list)

Forbidden practices — they break declarative purity or system hygiene.

1. `nix-env -i ANYTHING`. Period.
2. Editing files inside `/home/$USER/.config/<app>/` that are HM-symlinked.
3. Editing files inside `/etc/` outside this flake.
4. `sudo mkdir /usr/local/bin && cp` of pre-built binaries.
5. `pip install --user`, `npm install -g`, `cargo install`, `gem install`.
6. `flatpak install` — declarative alternative is a derivation.
7. Disabling pre-commit hooks (`--no-verify`).
8. Force-pushing to `main`.
9. Committing without `nixos-rebuild test` first.
10. Changing `system.stateVersion` (it pins behavioural defaults).
11. `allowUnfree` per-package — use the global flag in `nix.nix`.
12. Imperative `systemctl enable/disable` for things the flake should
    own.
13. Storing secrets in `.nix` files (not even commented out).
14. `git rebase -i main` after pushing.

---

## 8. Quick reference

### Fish shell shortcuts (defined in `home/fish.nix`)

```
rebuild         sudo nixos-rebuild switch --flake /etc/nixos &| nom
rebuild-test    sudo nixos-rebuild test   --flake /etc/nixos &| nom
gc              nix-collect-garbage --delete-older-than 14d (system + user)
oc              cd /etc/nixos
tokens-edit     edit /etc/nixos/secrets/tokens.age via agenix
keys            abbreviation for tokens-edit
omo             opencode + Nix-store oh-my-openagent plugin (`omo upd` updates package)
omp             oh-my-pi standalone coding agent (`omp upd` updates package)
flu             nix flake update
fls             nix flake show
flc             nix flake check
jf              journalctl -u <unit> --follow
jb              journalctl -b
ipa             ip -br -c addr
dps             docker ps
ports           ss -tlnp
sizeof          du -sh
md              mkdir -p && cd
```

### Display scale and terminal size

The built-in panel is pinned in Hyprland as:

```nix
"eDP-1, 2880x1800@120, 0x0, 1.8"
```

That makes the logical workspace `1600×1000`. The previous scale `2`
was `1440×900`; scale `1.5` was tested and gave `1920×1200`, but was
left as too small for the current UI balance.

Ghostty uses:

```text
font-size = 10.8
```

Config paths:

- `home/desktop/sessions/hyprland/session.nix` — monitor scale.
- `theme/ghostty.nix` — terminal font size.

### Waybar runtime note

After a rebuild/test that touches Hyprland or Waybar files, restart Waybar:

```fish
systemctl --user restart waybar
```

Reason: `hyprland/workspaces` can keep stale IPC state after Hyprland
reloads; the symptom is workspace switching works, but the active workspace
highlight in Waybar does not move. See `lessons/0005-waybar-workspace-stale-after-hyprland-reload.md`.

### Waybar host widgets

The Lecoo ultra-economy widget is `custom/ultra-economy` and renders the
`nf-md-opacity` glyph `󰗌`. Off-state uses normal foreground; on-state uses
`@bright_green` with a small glow. Toggling ultra-economy does not change
screen brightness; the current user-selected brightness is preserved.

Config paths:

- `hosts/lecoo/home/scripts.nix` — JSON text/class for the widget.
- `theme/waybar/default.nix` — font size and colours.

### Waybar power menu

The power button in Waybar and the laptop hardware power key open
`wlogout --buttons-per-row 2`. The hardware button is handled by Hyprland
for short presses; long press remains a logind emergency poweroff fallback.
It shows a four-button grid:

| Button | Key | Action |
|--------|-----|--------|
| Lock | `l` | `hyprlock` |
| Logout | `e` | `hyprctl dispatch exit` |
| Shutdown | `s` | `systemctl poweroff` |
| Reboot | `r` | `systemctl reboot` |

Config lives in `home/wlogout.nix`; icons live in `assets/wlogout-icons/`.
### Hyprland key bindings (defined in `home/desktop/sessions/hyprland/session.nix`)

```
SUPER+Return       terminal (Ghostty)
SUPER+B            Firefox
SUPER+D            rofi launcher
SUPER+Q            kill active window
SUPER+V            toggle floating
SUPER+F            fullscreen
Power key          wlogout power menu
SUPER+C            clipboard history (rofi)
SUPER+G            toggle window group (tabbed)
SUPER+Tab          next group tab
SUPER+1..9         switch workspace
SUPER+SHIFT+1..9   move window to workspace
SUPER+h/j/k/l      focus
SUPER+SHIFT+h/j/k/l move window
SUPER+CTRL+h/j/k/l resize
Print              full-screen screenshot
SUPER+Print        region screenshot
SUPER+SHIFT+Print  window screenshot
```

### Files you'll touch most

- `modules/nixos/packages.nix` — add a system CLI
- `home/<app>.nix` — add or change per-user app
- `home/desktop/sessions/hyprland/session.nix` — keybinds, window rules
- `theme/waybar.nix` / `theme/mako.nix` / `theme/rofi.nix` — UI styling
- `lib/palette.nix` — colour palette source of truth
- `secrets/<name>.age` — encrypted secrets

For everything else, search the file tree by filename. The structure
is small enough to keep in your head.
