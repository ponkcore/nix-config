# Architecture

> System reference for ponkcore's portable NixOS flake.
> Last revised: 2026-05-19 (multi-desktop architecture).

## TL;DR

Single-flake, multi-host portable NixOS configuration. Three composable
layers, one primary user, declarative end-to-end including secrets.
A fourth orthogonal axis — **desktop sessions** — lets each host pick
which Wayland compositors to install (Hyprland today; niri / GNOME
slot in without touching existing sessions).

```
                 ┌─────────────────────────────────┐
                 │  flake.nix                      │
                 │    nixosConfigurations.<host> ──┼──── lib/mkHost.nix
                 │       desktops, defaultSession  │       (specialArgs)
                 └────────────┬────────────────────┘
                              │
                              ▼
             ┌──────────────────────────────────┐
             │  hosts/<host>/default.nix        │
             │  imports                         │
             │    + ./hardware-configuration    │
             │    + modules/hardware/*          │
             │    + host-specific quirks        │
             │  hostname/username injected      │
             └─────────┬────────────────────────┘
                       │
         ┌─────────────┴───────────────┐
         ▼                             ▼
 ┌───────────────────┐         ┌───────────────────────┐
 │ modules/nixos/    │         │ modules/hardware/     │
 │ universal layer   │         │ opt-in classes        │
 │   - boot          │         │   cpu/amd             │
 │   - nix daemon    │         │   gpu/amd             │
 │   - users         │         │   form-factor/laptop  │
 │   - networking    │         │   (intel/nvidia/...   │
 │   - security      │         │    added on demand)   │
 │   - desktop/   ◄──┼─ reads ─┤                       │
 │   - secrets       │ desktops│                       │
 │   - sync          │         └───────────────────────┘
 │   ...             │
 └───────────────────┘
                       │
                       ▼
               ┌──────────────────┐
               │ home/            │
               │ Home Manager     │
               │ per-user config  │
               │   + desktop/  ◄──┼─ reads desktops
               └──────────────────┘
                       │
                       ▼
               ┌──────────────────────────┐
               │ theme/                   │
               │ compositor-agnostic UI   │
               │ (waybar, mako, rofi,     │
               │  ghostty, palette)       │
               └──────────────────────────┘
```

## Layer responsibilities

### Universal — `modules/nixos/`

Everything that should hold on any x86_64 host with a graphical session:
nix daemon settings, user account skeleton, locale, networking, security
hardening, fonts, virtualisation, secrets infrastructure, file sync,
and the **desktop dispatcher** (see below).

Does NOT touch: anything CPU-vendor-specific, anything GPU-vendor-
specific, anything form-factor-specific (lid, autosuspend), anything
single-machine quirky.

Aggregator: `modules/nixos/default.nix` imports every leaf. Hosts pick
up the whole layer via the import in `lib/mkHost.nix`.

### Hardware-class — `modules/hardware/`

Opt-in profiles. A host imports the ones that match its physical reality.

| Profile | Provides |
|---------|----------|
| `cpu/amd.nix` | `amd_pstate=active`, microcode, `kvm-amd`, IOMMU |
| `gpu/amd.nix` | `amdgpu` initrd module, Mesa, VAAPI, VDPAU bridge |
| `form-factor/laptop.nix` | `power-profiles-daemon` battery/charger profiles (AC-edge udev switching), lid handling (logind ignore + `lid-monitor` user service polling `/proc/acpi` for Hyprland DPMS), USB autosuspend rules, NVMe scheduler tuning, XHCI/I2C wakeup disable |

Future profiles slot in cleanly: `cpu/intel.nix` (intel_pstate, microcode,
kvm-intel), `gpu/nvidia.nix` (proprietary driver, Optimus), `gpu/intel.nix`
(i915, intel-media-driver), `form-factor/desktop.nix` (no battery, ATX
power policy), `form-factor/vm.nix` (qemu-guest-agent, spice-vdagent).

### Host — `hosts/<name>/`

Composition file plus host-only specifics.

```
hosts/lecoo/
├── default.nix              imports + system.stateVersion + EC enable
├── hardware-configuration.nix   generated mounts + initrd modules
├── hardware.nix             rtw89 quirks, NVMe ACPI, 8250.nr_uarts=0
└── ec.nix                   ITE IT5571 EC daemon
```

`default.nix` is short on purpose — the heavy lifting lives in modules.

### Desktop sessions — `modules/nixos/desktop/` + `home/desktop/`

Orthogonal to the three primary layers: an axis along which each host
picks zero or more Wayland compositors. The host declares its choice
once via `mkHost { desktops = [...]; defaultSession = "..."; }` in
`flake.nix`, and two parallel dispatchers fan it out.

```
modules/nixos/desktop/             home/desktop/
├── default.nix    (dispatcher)    ├── default.nix    (dispatcher)
├── common.nix     (always)        │     reads `desktops`,
│   portals, polkit, env vars      │     imports ../../theme +
├── greeter/                       │     selected sessions/
│   └── greetd.nix (default)       └── sessions/
│   (gdm.nix lands here when             ├── hyprland/
│    GNOME is added)                     │   ├── default.nix
└── sessions/                            │   ├── session.nix
    └── hyprland.nix                     │   ├── lock.nix
        (programs.hyprland,              │   ├── idle.nix
         UWSM, portal,                   │   └── paper.nix
         silent wrapper)                 (niri/, gnome/ when added)

theme/                             ── compositor-agnostic UI
├── default.nix      palette + scripts via _module.args
├── waybar.nix       waybar (hyprland workspace plugin guarded by mkIf)
├── mako.nix · rofi.nix · ghostty.nix · scripts.nix
```

The dispatchers' contract: importing a session module never affects
behaviour for sessions the host has not selected, and adding a new
session is a folder-scale change with no edits to existing sessions.

Greeter selection is automatic: `gdm` if `gnome ∈ desktops`, otherwise
`greetd + sway-kiosk + nwg-hello`. A host with an empty (or missing)
`desktops` list gets nothing from the desktop layer — useful for
headless / VM hosts.

## Inputs (flake.nix)

| Input | Role | Pins own nixpkgs? |
|-------|------|-------------------|
| `nixpkgs` | base package set, channel `nixos-26.05` | n/a |
| `home-manager` | user environment | follows |
| `nur` | community Firefox extensions | follows |
| `agenix` | encrypted secrets | follows nixpkgs + home-manager |
| `llm-agents` | opencode binary | does NOT follow — see decisions/0003 |
| `letta-code` | memory-first coding agent (talos runtime) | follows |

## Build flow

```
flake.nix
   ├── lib/mkHost.nix builds nixosSystem
   │      • specialArgs = { inputs, hostname, username,
   │                         desktops, defaultSession }
   │      • imports modules/nixos (universal)
   │      • imports home-manager NixOS module
   │      • registers pkgs/default.nix overlay list
   │      • sets networking.hostName from arg
   │      • plugs home/ as the user's HM profile
   │      • asserts defaultSession is set when len desktops > 1
   │
   └── plus host modules from hosts/<name>/default.nix
```

`pkgs/default.nix` returns a list of overlays:
- local packages (`cloakbrowser`, `orbit`, `oh-my-pi`, `oh-my-openagent`,
  `letta-code`, `mcp-bridge`, `context7-mcp`, `fetch-py`)
- NUR

## Secrets pipeline

```
secrets/<name>.age              ← encrypted with age, in repo
       │
       │ at activation
       ▼
agenix NixOS module decrypts using /etc/ssh/ssh_host_ed25519_key
       │
       ▼
/run/agenix.d/<gen>/<name>      ← ramfs, atomic generation swap
       │
       ▼
/run/agenix/<name>              ← stable symlink, mode 400, owner=user
       │
       ▼
home.activation reads it       ← e.g. opencode.json populated with apiKey
```

Authorisation list is `secrets/secrets.nix`. Both the host SSH host key
(for activation-time decryption) and user editor SSH keys (for
`agenix -e`) are listed there. Edit-flow: `cd secrets && agenix -e <f>`.

## Desktop stack (Hyprland session, current)

```
greetd → sway (Wayland kiosk) → nwg-hello (GTK3 greeter)
                                       │
                                       ▼
                                     UWSM
                                       │
                                       ▼
                                  Hyprland
                                       │
   ┌───────────────────────────────────┴───┐
   ▼                                       ▼
 user systemd units                  Hyprland-managed
   waybar                              hyprpaper
   mako (D-Bus activated)              hyprlock
   cliphist                            hypridle (lock/sleep hooks +
   wlsunset                                     idle-flag signal)
   lid-monitor ──── polls flag ────→
     sole owner of DPMS/backlight
     (laptop hosts only)
```

Palette: `lib/palette.nix` — 25 Gruvbox dark medium tokens. Distributed to
theme modules via `_module.args.p`, to a few HM modules by direct
import (`fzf.nix`, `wlogout.nix`, `yazi.nix`, `fish.nix`,
`modules/nixos/desktop/greeter/greetd.nix`).

## Cross-device password / secrets sync

```
                 KeePassXC (NixOS)              KeePassDX (Android)
                  ~/Documents/secrets/           Documents/secrets/
                  vault.kdbx                     vault.kdbx
                       │                              │
                       └──────── Syncthing ───────────┘
                                  P2P TLS
                                       │
                                       ▼ optionally ▼
                                 Encrypted USB
                                 (mirror, cold)
```

System-level: `modules/nixos/sync.nix` (Syncthing daemon, GUI on
127.0.0.1:8384). Per-user: `home/keepassxc.nix` (programs.keepassxc with
sensible defaults, browser native-messaging auto-registered).

Layer 1 secrets (system API keys) live in `secrets/*.age` via agenix.
Layer 2 (web/banking/notes/2FA) lives in the KeePass vault. Layer 3
(file sync, including the .kdbx itself) goes via Syncthing.

## What's where for non-trivial responsibilities

| Responsibility | Module |
|----------------|--------|
| Boot timing & quietness | `modules/nixos/boot.nix` |
| Power management policy | `modules/hardware/form-factor/laptop.nix` |
| Display blanking (lid + idle) | `modules/hardware/form-factor/laptop.nix` (lid-monitor) + `home/desktop/sessions/hyprland/idle.nix` (hypridle flag signal) |
| Custom EC daemon | `hosts/lecoo/ec.nix` (NixOS module providing `services.lecoo-ctrl`) |
| WiFi (rtw89) quirks | `hosts/lecoo/hardware.nix` |
| sysctl hardening | `modules/nixos/security.nix` |
| Firewall + SSH | `modules/nixos/security.nix` |
| Tailscale (manual start) | `modules/nixos/tailscale.nix` |
| Systemd shutdown timeouts | `modules/nixos/systemd.nix` |
| GC + auto-optimise + journald | `modules/nixos/nix.nix` |
| TRIM cadence | `modules/nixos/maintenance.nix` |
| CloakBrowser stealth Chromium | `pkgs/cloakbrowser/default.nix` |
| CloakBrowser profile manager | `home/cloakbrowser.nix` (`cb`/`cb-profile`) |
| `.hm-backup` cleanup | `home/cleanup.nix` |
| Desktop session dispatcher (system) | `modules/nixos/desktop/default.nix` |
| Desktop session dispatcher (user) | `home/desktop/default.nix` |
| greetd / nwg-hello styling | `modules/nixos/desktop/greeter/greetd.nix` |
| Hyprland system enable + UWSM | `modules/nixos/desktop/sessions/hyprland.nix` |
| Hyprland user config | `home/desktop/sessions/hyprland/` |
| Gruvbox palette source | `lib/palette.nix` |
