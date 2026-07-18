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
      keys = "tokens-edit";
    };

    interactiveShellInit = ''
      # Disable fish greeting
      set -g fish_greeting

      # Apply Caelestia terminal colour scheme to new sessions.
      # Caelestia CLI writes OSC sequences to sequences.txt on
      # `caelestia scheme set` and broadcasts to open PTYs, but
      # new terminal windows don't receive the broadcast. This
      # hook applies the saved sequences at interactive shell
      # startup so new Ghostty windows adopt the active scheme.
      # Sequences are idempotent (re-applying the same colours
      # is harmless). Skipped on dumb terminals and when the
      # file doesn't exist (first boot before Caelestia runs).
      if test "$TERM" != dumb -a -f "$HOME/.local/state/caelestia/sequences.txt"
        cat "$HOME/.local/state/caelestia/sequences.txt"
      end

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
      # tokens-edit — open the agenix-encrypted API token bundle in $EDITOR.
      # The decrypted secret lives only in agenix's temporary edit flow; do
      # not read /run/agenix/tokens directly just to inspect values.
      tokens-edit = ''
        cd /etc/nixos/secrets
        agenix -e tokens.age
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
      # omp — run oh-my-pi. `omp update [VERSION]` updates the declarative
      # Nix package pin instead of letting the upstream self-updater write into
      # the read-only Nix store.
      omp = ''
        if test (count $argv) -gt 0; and test "$argv[1]" = update
          cd /etc/nixos
          ./pkgs/oh-my-pi/update.sh $argv[2..]
          return $status
        end
        # GitHub token: injected at runtime (moved from HM activation
        # to avoid gh auth token in the boot path). omp expands
        # ''${GITHUB_TOKEN} in mcp.json from the process environment.
        set -l gh_token (gh auth token 2>/dev/null)
        if test -n "$gh_token"
          set -lx GITHUB_TOKEN "$gh_token"
        else
          echo "omp: gh auth token returned empty — GitHub MCP will fail." >&2
        end
        command omp $argv
      '';
      # omo — launch opencode with the Nix-store oh-my-openagent plugin.
      # `omo update [VERSION]` updates the local package pin; regular `omo ...`
      # injects the generated file:// plugin spec into OPENCODE_CONFIG_CONTENT.
      # Also injects the GitHub token (from `gh auth token`) at runtime —
      # the on-disk opencode.json has a placeholder that is substituted here.
      # Vanilla `opencode` has its own wrapper for token injection.
      omo = ''
        if test (count $argv) -gt 0; and test "$argv[1]" = update
          cd /etc/nixos
          ./pkgs/oh-my-openagent/update.sh $argv[2..]
          return $status
        end

        set -l cfg "$HOME/.config/opencode/opencode.json"
        set -l plugin_file "$HOME/.config/opencode/oh-my-openagent.plugin"
        if not test -f "$cfg"
          echo "ERROR: $cfg not found" >&2
          return 1
        end
        if not test -f "$plugin_file"
          echo "ERROR: $plugin_file not found" >&2
          return 1
        end

        set -l plugin (string trim < "$plugin_file")
        set -l gh_token (gh auth token 2>/dev/null)
        if test -z "$gh_token"
          echo "omo: gh auth token returned empty — GitHub MCP will fail." >&2
        end
        set -l updated (jq --arg plugin "$plugin" --arg ghtoken "$gh_token" '.plugin = ((.plugin // []) | map(select((type == "string" and (test("^oh-my-open(agent|code)(@.*)?$") or test("oh-my-openagent"))) | not)) + [$plugin]) | .mcp.github.environment.GITHUB_PERSONAL_ACCESS_TOKEN = $ghtoken' "$cfg")
        OMO_DISABLE_POSTHOG=1 OPENCODE_CONFIG_CONTENT="$updated" command opencode $argv
      '';
      # opencode — vanilla launch with runtime GitHub token injection.
      # The on-disk opencode.json contains a placeholder token (written
      # by HM activation without calling gh); this wrapper substitutes
      # the real token from `gh auth token` at launch time via
      # OPENCODE_CONFIG_CONTENT, so the token never touches /nix/store.
      # Use `command opencode` to bypass this wrapper if needed.
      opencode = ''
        set -l cfg "$HOME/.config/opencode/opencode.json"
        if not test -f "$cfg"
          command opencode $argv
          return $status
        end
        set -l gh_token (gh auth token 2>/dev/null)
        if test -z "$gh_token"
          echo "opencode: gh auth token returned empty — GitHub MCP will fail." >&2
        end
        set -l updated (jq --arg ghtoken "$gh_token" '.mcp.github.environment.GITHUB_PERSONAL_ACCESS_TOKEN = $ghtoken' "$cfg")
        OPENCODE_CONFIG_CONTENT="$updated" command opencode $argv
      '';
      # ── Tailscale helpers ───────────────────────────────────────────
      # Tailscaled and a proxy TUN cannot run together (DNS hijacking +
      # default-route conflict — see modules/nixos/tailscale.nix). The
      # helpers below make manual juggling painless.
      #
      # ts-on  : ensure no proxy TUN is up, start tailscaled, run `up`.
      # ts-off : run `down` and stop tailscaled (proxy stays as-is).
      # ts     : passthrough to `tailscale` so `ts status`, `ts ping`,
      #          `ts ip`, etc. work without typing the full name. With
      #          no arguments — `tailscale status`.
      ts-on = ''
        # Refuse to start while a proxy TUN is active. Clash Verge
        # (mihomo) creates the `Mihomo` (system stack) or `Meta`
        # (gVisor stack) TUN; Throne creates `throne-tun`. Both
        # conflict with tailscaled on DNS hijack + default-route
        # ownership. TUN devices report state UNKNOWN in `ip -br`
        # (no link layer), so we check for interface existence via
        # `ip link show` instead of matching the state column.
        set tun_found 0
        for iface in Mihomo Meta throne-tun
          if ip link show $iface >/dev/null 2>&1
            set tun_found 1
            break
          end
        end
        if test $tun_found -eq 1
          echo "ERROR: a proxy TUN (Clash Verge / Throne) appears to be up. Disable it first." >&2
          echo "       Hint: clash-verge-toggle (GUI) or throne-toggle, then re-run ts-on." >&2
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

  # Prompt: starship — Gruvbox dark medium palette, informative but compact
  programs.starship = {
    enable = true;
    settings = {
      add_newline = true;
      format = "╭─$username$hostname in $directory$git_branch$git_status$nix_shell$cmd_duration$fill$time\n╰─$character";

      username = {
        disabled = false;
        show_always = true;
        style_user = "bold #d4bd99";
        style_root = "bold #fb4934";
        format = "[$user]($style)";
      };

      hostname = {
        disabled = false;
        ssh_only = false;
        style = "bold #83a598";
        format = "[@$hostname]($style)";
      };

      character = {
        success_symbol = "[➜](bold #b8bb26)";
        error_symbol = "[➜](bold #fb4934)";
      };

      directory = {
        style = "bold #d4bd99";
        truncation_length = 4;
        truncation_symbol = ".../";
        format = "[$path]($style)";
      };

      git_branch = {
        style = "bold #83a598";
        symbol = "";
        format = " on [$branch(:$remote_branch)]($style)";
      };

      git_status = {
        style = "#fabd2f";
        format = " [$all_status$ahead_behind]($style)";
      };

      nix_shell = {
        symbol = "󱄅";
        style = "bold #8ec07c";
        format = " [$symbol $state]($style)";
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
        format = " took [$duration]($style)";
      };

      fill = {
        symbol = " ";
      };

      time = {
        disabled = false;
        style = "#a89984";
        time_format = "%R";
        format = "[$time]($style)";
      };
    };
  };
}
