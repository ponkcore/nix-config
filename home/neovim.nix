# neovim.nix — primary editor.
#
# Fully declarative: every plugin and every treesitter parser is
# pinned via nixpkgs, no runtime cloning, no lazy.nvim bootstrap.
# Native LSP (Neovim 0.11+ vim.lsp.config / vim.lsp.enable) +
# nvim-cmp completion + telescope finder + gruvbox + conform
# (format-on-save) + autopairs + comment + indent-blankline.
{pkgs, ...}: {
  programs.neovim = {
    enable = true;
    vimAlias = true;

    # LSP servers and formatters (resolved via PATH at runtime by
    # the corresponding plugin specs below).
    extraPackages = with pkgs; [
      # LSP servers
      lua-language-server
      nil
      typescript-language-server
      vscode-langservers-extracted
      pyright
      marksman
      # Formatters (conform.nvim)
      alejandra
      nixfmt-rfc-style
      prettierd
      stylua
      shfmt
      ruff
    ];

    # Every plugin lives in /nix/store and is pre-loaded by neovim's
    # built-in pack-dir mechanism — no lazy.nvim, no runtime fetch,
    # no auto-installer. Treesitter parsers come bundled with the
    # `nvim-treesitter.withPlugins` derivation; they land next to
    # the plugin's own `parser/` directory and neovim picks them up
    # via the standard runtimepath. Plugin-specific configuration
    # lives in `extraLuaConfig` below.
    plugins = with pkgs.vimPlugins; [
      # Treesitter — parsers + queries baked into one derivation.
      # The list below covers every language we open in this
      # editor today; `markdown_inline` is required by `markdown`,
      # `vim` + `vimdoc` come for free with neovim itself but
      # listing them here keeps the highlight queries consistent.
      (nvim-treesitter.withPlugins (p:
        with p; [
          lua
          nix
          typescript
          javascript
          python
          go
          rust
          bash
          json
          yaml
          toml
          markdown
          markdown-inline
          html
          css
          regex
          vim
          vimdoc
        ]))

      # Colorscheme
      gruvbox-nvim

      # Finder
      telescope-nvim
      plenary-nvim # telescope dependency

      # LSP
      nvim-lspconfig

      # Completion
      nvim-cmp
      cmp-nvim-lsp
      cmp-buffer
      cmp-path
      lspkind-nvim

      # Statusline
      lualine-nvim

      # File tree
      nvim-tree-lua
      nvim-web-devicons

      # Git
      gitsigns-nvim

      # Helpers
      which-key-nvim
      conform-nvim # format-on-save
      nvim-autopairs
      comment-nvim
      indent-blankline-nvim
    ];

    # 26.05: extraLuaConfig renamed to initLua (auto-migrated with
    # deprecation warning, but renamed for future-proofing).
    initLua = ''
      -- ── Leader ──────────────────────────────────────────────────────
      vim.g.mapleader = " "
      vim.g.maplocalleader = " "

      -- ── Basic settings ──────────────────────────────────────────────
      vim.opt.number = true
      vim.opt.relativenumber = true
      vim.opt.signcolumn = "yes"
      vim.opt.termguicolors = true
      vim.opt.clipboard = "unnamedplus"
      vim.opt.expandtab = true
      vim.opt.shiftwidth = 2
      vim.opt.tabstop = 2
      vim.opt.smartindent = true
      vim.opt.undofile = true
      vim.opt.ignorecase = true
      vim.opt.smartcase = true
      vim.opt.updatetime = 250
      vim.opt.timeoutlen = 300
      vim.opt.splitright = true
      vim.opt.splitbelow = true
      vim.opt.inccommand = "split"
      vim.opt.scrolloff = 8
      vim.opt.cursorline = true

      -- ── Treesitter ──────────────────────────────────────────────────
      -- Neovim 0.12+ has built-in treesitter highlighting and indentation
      -- enabled by default when parsers are installed. The parsers are
      -- baked into /nix/store via nvim-treesitter.withPlugins (see
      -- programs.neovim.plugins). The old `require("nvim-treesitter.
      -- configs").setup({highlight = {enable = true}})` API was removed
      -- in nvim-treesitter 0.10+ (2026-04). No setup call needed.

      -- ── Colorscheme ─────────────────────────────────────────────────
      require("gruvbox").setup({
        contrast = "hard",
        transparent_mode = false,
        overrides = {
          SignColumn = {bg = "#1d2021"},
        },
      })
      vim.cmd.colorscheme("gruvbox")

      -- ── Telescope ───────────────────────────────────────────────────
      do
        local builtin = require("telescope.builtin")
        vim.keymap.set("n", "<leader>ff", builtin.find_files, {desc = "Find files"})
        vim.keymap.set("n", "<leader>fg", builtin.live_grep, {desc = "Live grep"})
        vim.keymap.set("n", "<leader>fb", builtin.buffers, {desc = "Buffers"})
        vim.keymap.set("n", "<leader>fh", builtin.help_tags, {desc = "Help tags"})
        vim.keymap.set("n", "<leader>fd", builtin.diagnostics, {desc = "Diagnostics"})
      end

      -- ── LSP — Neovim 0.11+ native API ───────────────────────────────
      -- nvim-lspconfig v2+ ships server presets under runtime/lsp/<server>.lua;
      -- vim.lsp.enable picks them up automatically. vim.lsp.config('*', ...)
      -- merges in our default capabilities (cmp completions) for every server.
      do
        local capabilities = require("cmp_nvim_lsp").default_capabilities()
        vim.lsp.config("*", {capabilities = capabilities})
        vim.lsp.enable({
          "lua_ls",
          "nil_ls",
          "ts_ls",
          "gopls",
          "pyright",
          "jsonls",
          "html",
          "cssls",
          "bashls",
          "marksman",
        })

        vim.keymap.set("n", "gd", vim.lsp.buf.definition, {desc = "Go to definition"})
        vim.keymap.set("n", "gr", vim.lsp.buf.references, {desc = "References"})
        vim.keymap.set("n", "gi", vim.lsp.buf.implementation, {desc = "Implementation"})
        vim.keymap.set("n", "K", vim.lsp.buf.hover, {desc = "Hover"})
        vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename, {desc = "Rename"})
        vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action, {desc = "Code action"})
        vim.keymap.set("n", "<leader>d", vim.diagnostic.open_float, {desc = "Line diagnostics"})
        vim.keymap.set("n", "[d", vim.diagnostic.goto_prev, {desc = "Prev diagnostic"})
        vim.keymap.set("n", "]d", vim.diagnostic.goto_next, {desc = "Next diagnostic"})
      end

      -- ── Completion ──────────────────────────────────────────────────
      do
        local cmp = require("cmp")
        local lspkind = require("lspkind")
        cmp.setup({
          formatting = {
            format = lspkind.cmp_format({mode = "symbol_text"}),
          },
          mapping = cmp.mapping.preset.insert({
            ["<C-b>"] = cmp.mapping.scroll_docs(-4),
            ["<C-f>"] = cmp.mapping.scroll_docs(4),
            ["<C-Space>"] = cmp.mapping.complete(),
            ["<C-e>"] = cmp.mapping.abort(),
            ["<CR>"] = cmp.mapping.confirm({select = true}),
            ["<Tab>"] = cmp.mapping.select_next_item(),
            ["<S-Tab>"] = cmp.mapping.select_prev_item(),
          }),
          sources = cmp.config.sources({
            {name = "nvim_lsp"},
            {name = "path"},
          }, {
            {name = "buffer"},
          }),
        })
      end

      -- ── Statusline ──────────────────────────────────────────────────
      require("lualine").setup({
        options = {
          theme = "gruvbox",
          icons_enabled = true,
          section_separators = "",
          component_separators = "|",
        },
        sections = {
          lualine_a = {"mode"},
          lualine_b = {"branch", "diff", "diagnostics"},
          lualine_c = {{"filename", path = 1}},
          lualine_x = {"encoding", "fileformat", "filetype"},
          lualine_y = {"progress"},
          lualine_z = {"location"},
        },
      })

      -- ── File tree ───────────────────────────────────────────────────
      require("nvim-tree").setup({
        view = {width = 30},
        renderer = {group_empty = true},
        filters = {dotfiles = false},
      })
      vim.keymap.set("n", "<leader>e", ":NvimTreeToggle<CR>", {desc = "Toggle file tree", silent = true})

      -- ── Git signs ───────────────────────────────────────────────────
      require("gitsigns").setup({
        signs = {
          add = {text = "+"},
          change = {text = "~"},
          delete = {text = "_"},
          topdelete = {text = "‾"},
          changedelete = {text = "~"},
        },
      })

      -- ── Which-key ───────────────────────────────────────────────────
      require("which-key").setup({})

      -- ── Format on save ──────────────────────────────────────────────
      require("conform").setup({
        formatters_by_ft = {
          nix = {"alejandra"},
          lua = {"stylua"},
          javascript = {"prettierd"},
          typescript = {"prettierd"},
          json = {"prettierd"},
          yaml = {"prettierd"},
          html = {"prettierd"},
          css = {"prettierd"},
          markdown = {"prettierd"},
          python = {"ruff_format"},
          go = {"gofmt"},
          rust = {"rustfmt"},
          sh = {"shfmt"},
          bash = {"shfmt"},
        },
        format_on_save = {
          timeout_ms = 2000,
          lsp_fallback = true,
        },
      })

      -- ── Auto-pairs ──────────────────────────────────────────────────
      require("nvim-autopairs").setup({})

      -- ── Comment (gcc / gc<motion>) ──────────────────────────────────
      require("Comment").setup({})

      -- ── Indent guides ───────────────────────────────────────────────
      require("ibl").setup({
        indent = {char = "│"},
        scope = {enabled = true, show_start = false, show_end = false},
      })
    '';
  };
}
