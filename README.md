# nix-config

> Portable NixOS flake managing a single user across any number of
> machines. Single source of truth for kernel, packages, dotfiles,
> services, and secrets.

```
NixOS 25.11   ·   Hyprland   ·   Gruvbox-warm palette   ·   home-manager   ·   agenix
```

## What this is

A multi-host NixOS flake decomposed into three layers so a new
device gets fully provisioned in ten minutes. The whole machine —
from kernel parameters to which Firefox extensions are pinned — is
declarative. Encrypted secrets live in the repository alongside the
code; password storage and cross-device sync are first-class.

```
modules/nixos/        universal layer — works on any x86_64 host
modules/hardware/     opt-in profiles per CPU / GPU / form-factor
hosts/<name>/         host composition — picks profiles + adds quirks
```

Adding a new device: drop a file under `hosts/<name>/`, list which
hardware profiles to import, run `nixos-install`. That's it.

## Hosts

| Host | Hardware | Profiles |
|------|----------|----------|
| `lecoo` | Lenovo Lecoo Pro 14 2025 (AMD Ryzen 7 H 255 / Radeon 780M) | cpu/amd, gpu/amd, form-factor/laptop |

## Highlights

- **Multi-host portability** — `nixosConfigurations.<name>` per device.
- **Encrypted secrets in repo** via [`agenix`](https://github.com/ryantm/agenix);
  decryption uses the host's SSH host key, no manual key distribution.
- **Three-layer password strategy** — agenix (system API keys) +
  KeePassXC (web/banking/2FA) + Syncthing (cross-device .kdbx and
  document mirror).
- **Custom Lecoo EC daemon** — fan curves, charge thresholds via the
  ITE IT5571 Super-I/O chip.
- **Aggressive boot quieting** — Plymouth abstract_ring theme on the
  internal eDP panel, systemd quiet flags, and greetd running
  nwg-hello inside a sway Wayland kiosk.
- **Reaper timers** — donut-proxy zombies (15-min sweep), HM-backup
  files (weekly purge).
- **Sysctl hardening pass** — `kexec_load_disabled`, redirect/source-
  route refusal, strict rp_filter, log_martians, tcp_rfc1337, etc.
- **AI agent stack** — Letta Code (`talos`), opencode, OMO
  (`opencode` + oh-my-openagent), and Antigravity CLI, with API keys
  managed declaratively via agenix.

## Stack

| Concern | Choice |
|---------|--------|
| Compositor | Hyprland (UWSM) |
| Display manager | greetd + nwg-hello inside sway Wayland kiosk |
| Status bar | Waybar |
| Notifications | mako |
| Launcher | rofi |
| Lock screen | hyprlock |
| Idle manager | hypridle |
| Wallpaper | hyprpaper |
| Terminal | Ghostty |
| Shell | fish + starship |
| Editor | Neovim 0.11 (nixpkgs-pinned plugins, native LSP) |
| File manager | Nautilus (GUI) + yazi (TUI) |
| Browser | Firefox (Arkenfox + NUR addons) |
| Audio | PipeWire + WirePlumber |
| Power | power-profiles-daemon + amd_pmf + lecoo-ec-daemon |
| Proxy | Clash Verge Rev (mihomo TUN) |
| Container | Docker (on-demand) |
| Virtualisation | libvirt + qemu_kvm |
| Mesh VPN | Tailscale (manual start) |
| Secrets | agenix |
| Password vault | KeePassXC + Syncthing |
| Sysadmin agent | Letta Code (`talos`) |
| Coding agents | opencode, OMO (`omo`), Antigravity CLI |

## Repository layout

```
flake.nix                Inputs + nixosConfigurations
flake.lock               Pinned input revisions
lib/
  mkHost.nix             Helper: builds a nixosSystem from a host spec
  palette.nix            Gruvbox-warm color tokens
hosts/
  lecoo/                 Lenovo Lecoo Pro 14 2025
modules/
  nixos/                 Universal layer (boot, security, services, …)
    desktop/             Wayland desktop stack
  hardware/              Opt-in profiles per CPU/GPU/form-factor/boot
home/                    Home Manager modules (per-user config)
theme/                   Wayland theme bundle (palette consumers)
pkgs/                    Local package derivations + overlay
secrets/                 agenix-encrypted secrets + authorisation map
skills/                  Letta Code skill files installed into ~/.letta/skills
tests/                   nixosTests exposed through flake checks
docs/
  architecture.md        System map for humans
  handbook.md            Daily ops & how-tos
  conventions.md         Code style and Git rules
  workflows.md           Step-by-step recipes
assets/                  Wallpapers, screenshots
AGENTS.md                LLM-agent contract: rules, conventions, boundaries
```

Full architecture diagram and module breakdown:
[`docs/architecture.md`](docs/architecture.md).

## Quickstart on existing hardware

```sh
# 1. Boot a NixOS 25.11 installer ISO on the target machine.
# 2. Partition + format + mount on /mnt (see docs/handbook.md §5).
# 3. Generate hardware-configuration:
sudo nixos-generate-config --root /mnt

# 4. Clone this flake to /mnt/etc/nixos.
sudo nix-shell -p git --run \
  'git clone https://github.com/ponkcore/nix-config /mnt/etc/nixos'

# 5. Create your host directory:
sudo cp /mnt/etc/nixos/hardware-configuration.nix \
        /mnt/etc/nixos/hosts/<your-host>/hardware-configuration.nix

# 6. Add hosts/<your-host>/default.nix listing the relevant
#    modules/hardware/* profiles. Register the host in flake.nix.

# 7. Authorise the new host's SSH host key in secrets/secrets.nix
#    on your dev machine; re-encrypt with agenix -r.

# 8. Install:
sudo nixos-install --flake /mnt/etc/nixos#<your-host>
```

Full ritual: [`docs/handbook.md`](docs/handbook.md) §5.

## Daily commands

```fish
rebuild                  # apply changes
rebuild-test             # try without committing to a boot entry
gc                       # collect old generations
flu                      # nix flake update
talos                    # Letta Code sysadmin agent in talos-brain
talos system <prompt>    # Letta Code sysadmin agent in /etc/nixos
omo                      # opencode with oh-my-openagent plugin
```

```sh
# Add a new encrypted secret:
cd secrets && agenix -e <name>.age
# editor opens, type plaintext, save & quit.

# Inspect timers, services, hardening:
systemctl --user list-timers
systemctl --failed
sysctl kernel.kexec_load_disabled net.ipv4.tcp_rfc1337
```

## Conventions

Conventional Commits, five pre-commit hooks (alejandra, statix,
deadnix, nil, gitleaks), `nixos-rebuild test` before `switch`.
Full rules: [`docs/conventions.md`](docs/conventions.md).

For LLM agents (Letta Code / opencode / OMO / claude code / cursor /
etc.) operating on this repo: read [`AGENTS.md`](AGENTS.md) first.

## License

MIT. See [`LICENSE`](LICENSE).
