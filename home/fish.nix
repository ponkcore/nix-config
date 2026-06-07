# fish.nix — friendly interactive shell.
# Aliases (no chains/pipes — fish alias generates a function that breaks
# on those), abbreviations (chain-safe, expand inline at typing time),
# fzf-driven keybinds, plus the starship prompt with the gruvbox palette.
_: {
  programs.fish = {
    enable = true;

    # Simple aliases (no pipes/chain operators — fish alias generates a function
    # and pipes/&& break the function syntax)
    shellAliases = {
      ls = "eza --icons";
      ll = "eza -l --icons --git";
      la = "eza -la --icons --git";
      cat = "bat --paging=never";
    };

    # Abbreviations for commands with pipes/chain operators — abbr expands inline
    # at typing time, so pipe and && operators work correctly
    shellAbbrs = {
      rebuild = "sudo nixos-rebuild switch --show-trace &| nom";
      rebuild-test = "sudo nixos-rebuild test --show-trace &| nom";
      gc = "sudo nix-collect-garbage -d && nix-collect-garbage -d";
      flu = "nix flake update";
      fls = "nix flake show";
      flc = "nix flake check";
      jf = "journalctl -fu";
      jb = "journalctl -b --no-pager | tail -100";
      ipa = "ip -br -c a";
      dps = "docker ps --format 'table {{.Names}}\\t{{.Status}}\\t{{.Ports}}'";
      ports = "ss -tlnp";
      sizeof = "du -sh";
      md = "mkdir -p";

      # Hyprland floating-window rescue — manually re-center any
      # floating window whose `at` fell outside its monitor's
      # logical rectangle (drift bug on mixed-scale eDP-1 + HDMI-A-1
      # under 0.52.1; see journal/2026-05-25, journal/2026-05-26).
      rc = "recenter-floating";
      rca = "recenter-floating --all";
    };

    interactiveShellInit = ''
      # Disable fish greeting
      set -g fish_greeting

      # Ctrl+E — edit current command in $EDITOR
      bind \ce edit_command_buffer

      # Ctrl+G — fzf git tracked files (opens in $EDITOR)
      bind \cg '__fzf_git_files'

      # Ctrl+B — fzf git branches (checkout)
      bind \cb '__fzf_git_branches'
    '';

    functions = {
      __fzf_git_files = ''
        if not git rev-parse --is-inside-work-tree >/dev/null 2>&1
          echo "Not a git repo" >&2
          return 1
        end
        set -l file (git ls-files --modified --others --exclude-standard | fzf --preview 'bat --color=always --style=numbers --line-range=:200 {}' --height 60% --border)
        if test -n "$file"
          commandline -r "$EDITOR $file"
          commandline -f execute
        end
      '';
      __fzf_git_branches = ''
        if not git rev-parse --is-inside-work-tree >/dev/null 2>&1
          echo "Not a git repo" >&2
          return 1
        end
        set -l branch (git branch -a --format='%(refname:short)' | fzf --height 40% --border)
        if test -n "$branch"
          commandline -r "git checkout $branch"
          commandline -f execute
        end
      '';
      # oc — cd to /etc/nixos (system flake root)
      oc = ''
        cd /etc/nixos
      '';
      # age-pub — print the ed25519 public keys used by agenix
      # (host key from /etc/ssh, user key from ~/.ssh).
      # These are the keys listed in secrets/secrets.nix.
      age-pub = ''
        echo "# host (lecoo)"
        cat /etc/ssh/ssh_host_ed25519_key.pub
        echo "# user (ponkcore)"
        cat ~/.ssh/id_ed25519.pub
      '';
      # sshkey — print the three-line snippet for adding the local
      # ed25519 public key to a remote host's ~/.ssh/authorized_keys.
      # Optional argument: path to a different pubkey (defaults to
      # ~/.ssh/id_ed25519.pub). Output is ready-to-paste into a
      # remote shell over a fresh password session.
      sshkey = ''
        set -l pubfile (test -n "$argv[1]"; and echo $argv[1]; or echo "$HOME/.ssh/id_ed25519.pub")
        if not test -f "$pubfile"
          echo "ERROR: $pubfile not found" >&2
          return 1
        end
        set -l pub (cat "$pubfile")
        echo "install -d -m 700 ~/.ssh"
        echo "echo '$pub' >> ~/.ssh/authorized_keys"
        echo "chmod 600 ~/.ssh/authorized_keys"
      '';
      # omo — launch opencode with oh-my-openagent plugin injected at runtime.
      # Reads ~/.config/opencode/opencode.json, adds the plugin to the array,
      # and passes the result via OPENCODE_CONFIG_CONTENT env var.
      # Vanilla `opencode` stays plugin-free for fast simple tasks.
      omo = ''
        set -l cfg "$HOME/.config/opencode/opencode.json"
        if not test -f "$cfg"
          echo "ERROR: $cfg not found" >&2
          return 1
        end
        set -l updated (jq '.plugin = ((.plugin // []) | if any(.[]; test("^oh-my-open(agent|code)(@.*)?$")) then . else . + ["oh-my-openagent@latest"] end)' "$cfg")
        OPENCODE_CONFIG_CONTENT="$updated" opencode $argv
      '';
      # ── Tailscale helpers ───────────────────────────────────────────
      # Tailscaled and throne TUN cannot run together (DNS hijacking +
      # default-route conflict — see modules/nixos/tailscale.nix). The
      # helpers below make manual juggling painless.
      #
      # ts-on  : ensure throne is down, start tailscaled, run `up`.
      # ts-off : run `down` and stop tailscaled (throne stays as-is).
      # ts     : passthrough to `tailscale` so `ts status`, `ts ping`,
      #          `ts ip`, etc. work without typing the full name. With
      #          no arguments — `tailscale status`.
      ts-on = ''
        # Refuse to start while throne TUN is active. Throne runs as a
        # systemd-wrapped user binary; the TUN is owned by throne-core
        # via security.wrappers. Detect by interface presence — if a
        # tun-style interface other than tailscale0 is up with a default
        # route, abort.
        if ip -br link show 2>/dev/null | grep -qE '^(throne|tun|utun|wg)[0-9]*\s+UP'
          echo "ERROR: throne (or another TUN VPN) appears to be up. Disable it first." >&2
          echo "       Hint: throne-toggle, then re-run ts-on." >&2
          return 1
        end
        sudo systemctl start tailscaled
        sudo tailscale up --accept-routes $argv
      '';
      ts-off = ''
        sudo tailscale down
        sudo systemctl stop tailscaled
      '';
      ts = ''
        if test (count $argv) -eq 0
          tailscale status
        else
          tailscale $argv
        end
      '';
    };
  };

  # Prompt: starship — gruvbox-warm palette, informative but compact
  programs.starship = {
    enable = true;
    settings = {
      add_newline = true;
      format = "$directory$git_branch$git_status$nix_shell$python$nodejs$rust$golang$cmd_duration$line_break$character";

      character = {
        success_symbol = "[➜](bold #b8bb26)";
        error_symbol = "[➜](bold #fb4934)";
      };

      directory = {
        style = "bold #d4bd99";
        truncation_length = 4;
        truncation_symbol = ".../";
      };

      git_branch = {
        style = "bold #83a598";
        symbol = " ";
        format = "[$symbol$branch(:$remote_branch)]($style) ";
      };

      git_status = {
        style = "#fabd2f";
        format = "[$all_status$ahead_behind]($style)";
      };

      nix_shell = {
        symbol = " ";
        style = "bold #8ec07c";
        format = "[$symbol$state]($style) ";
      };

      python = {
        symbol = " ";
        style = "#fabd2f";
        format = "[$symbol$version]($style) ";
      };

      nodejs = {
        symbol = " ";
        style = "#b8bb26";
        format = "[$symbol$version]($style) ";
      };

      rust = {
        symbol = " ";
        style = "#fb4934";
        format = "[$symbol$version]($style) ";
      };

      golang = {
        symbol = " ";
        style = "#83a598";
        format = "[$symbol$version]($style) ";
      };

      cmd_duration = {
        style = "#a89984";
        min_time = 2000;
        format = "[$duration]($style) ";
      };
    };
  };
}
