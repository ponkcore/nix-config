# neovim.nix — primary editor.
# lazy.nvim plugin manager + Treesitter + native LSP (0.11+) +
# nvim-cmp completion + telescope finder + gruvbox + conform
# (format-on-save) + autopairs + comment + indent-blankline.
{pkgs, ...}: {
  programs.neovim = {
    enable = true;
    vimAlias = true;

    # LSP servers and formatters
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

    # Only lazy.nvim as bootstrap — all other plugins managed by lazy.nvim
    plugins = with pkgs.vimPlugins; [
      lazy-nvim
    ];

    extraLuaConfig = ''
      -- Bootstrap lazy.nvim
      local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
      if not vim.loop.fs_stat(lazypath) then
        vim.fn.system({
          "git",
          "clone",
          "--filter=blob:none",
          "https://github.com/folke/lazy.nvim.git",
          "--branch=stable",
          lazypath,
        })
      end
      vim.opt.rtp:prepend(lazypath)

      -- Treesitter: ensure writable runtime path (outside /nix/store)
      vim.opt.runtimepath:prepend(vim.fn.stdpath("data") .. "/lazy/nvim-treesitter")

      -- Leader key (must be set before lazy)
      vim.g.mapleader = " "
      vim.g.maplocalleader = " "

      -- Basic settings
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

      -- Lazy setup with plugin specs
      require("lazy").setup({
        -- Colorscheme: Gruvbox (warm, matches system palette)
        {
          "ellisonleao/gruvbox.nvim",
          lazy = false,
          priority = 1000,
          config = function()
            require("gruvbox").setup({
              contrast = "hard",
              transparent_mode = false,
              overrides = {
                SignColumn = { bg = "#1d2021" },
              },
            })
            vim.cmd.colorscheme("gruvbox")
          end,
        },

        -- Telescope
        {
          "nvim-telescope/telescope.nvim",
          tag = "0.1.8",
          dependencies = { "nvim-lua/plenary.nvim" },
          config = function()
            local builtin = require("telescope.builtin")
            vim.keymap.set("n", "<leader>ff", builtin.find_files, { desc = "Find files" })
            vim.keymap.set("n", "<leader>fg", builtin.live_grep, { desc = "Live grep" })
            vim.keymap.set("n", "<leader>fb", builtin.buffers, { desc = "Buffers" })
            vim.keymap.set("n", "<leader>fh", builtin.help_tags, { desc = "Help tags" })
            vim.keymap.set("n", "<leader>fd", builtin.diagnostics, { desc = "Diagnostics" })
          end,
        },

        -- Treesitter — pin to master branch.
        -- nvim-treesitter migrated to a different API on the `main` branch
        -- (no more require("nvim-treesitter.configs").setup{}); master keeps
        -- the classic API our config below relies on.
        {
          "nvim-treesitter/nvim-treesitter",
          branch = "master",
          build = ":TSUpdate",
          config = function()
            require("nvim-treesitter.configs").setup({
              parser_install_dir = vim.fn.stdpath("data") .. "/treesitter-parsers",
              ensure_installed = { "lua", "nix", "typescript", "javascript", "python", "go", "rust", "bash", "json", "yaml", "toml", "markdown", "html", "css" },
              auto_install = true,
              highlight = { enable = true },
              indent = { enable = true },
            })
            -- Add parser dir to runtimepath so neovim finds the parsers
            vim.opt.runtimepath:append(vim.fn.stdpath("data") .. "/treesitter-parsers")
          end,
        },

        -- LSP — Neovim 0.11+ native API (vim.lsp.config + vim.lsp.enable).
        -- nvim-lspconfig v2+ ships server presets under runtime/lsp/<server>.lua;
        -- vim.lsp.enable picks them up automatically, vim.lsp.config('*', ...)
        -- merges in our default capabilities for every server.
        {
          "neovim/nvim-lspconfig",
          config = function()
            local capabilities = require("cmp_nvim_lsp").default_capabilities()

            vim.lsp.config("*", { capabilities = capabilities })

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

            -- Keymaps
            vim.keymap.set("n", "gd", vim.lsp.buf.definition, { desc = "Go to definition" })
            vim.keymap.set("n", "gr", vim.lsp.buf.references, { desc = "References" })
            vim.keymap.set("n", "gi", vim.lsp.buf.implementation, { desc = "Implementation" })
            vim.keymap.set("n", "K", vim.lsp.buf.hover, { desc = "Hover" })
            vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename, { desc = "Rename" })
            vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action, { desc = "Code action" })
            vim.keymap.set("n", "<leader>d", vim.diagnostic.open_float, { desc = "Line diagnostics" })
            vim.keymap.set("n", "[d", vim.diagnostic.goto_prev, { desc = "Prev diagnostic" })
            vim.keymap.set("n", "]d", vim.diagnostic.goto_next, { desc = "Next diagnostic" })
          end,
        },

        -- Completion
        {
          "hrsh7th/nvim-cmp",
          dependencies = {
            "hrsh7th/cmp-nvim-lsp",
            "hrsh7th/cmp-buffer",
            "hrsh7th/cmp-path",
          },
          config = function()
            local cmp = require("cmp")
            local lspkind = require("lspkind")

            cmp.setup({
              formatting = {
                format = lspkind.cmp_format({ mode = "symbol_text" }),
              },
              mapping = cmp.mapping.preset.insert({
                ["<C-b>"] = cmp.mapping.scroll_docs(-4),
                ["<C-f>"] = cmp.mapping.scroll_docs(4),
                ["<C-Space>"] = cmp.mapping.complete(),
                ["<C-e>"] = cmp.mapping.abort(),
                ["<CR>"] = cmp.mapping.confirm({ select = true }),
                ["<Tab>"] = cmp.mapping.select_next_item(),
                ["<S-Tab>"] = cmp.mapping.select_prev_item(),
              }),
              sources = cmp.config.sources({
                { name = "nvim_lsp" },
                { name = "path" },
              }, {
                { name = "buffer" },
              }),
            })
          end,
        },

        -- LSP kind icons
        { "onsails/lspkind.nvim" },

        -- Statusline
        {
          "nvim-lualine/lualine.nvim",
          config = function()
            require("lualine").setup({
              options = {
                theme = "gruvbox",
                icons_enabled = true,
                section_separators = "",
                component_separators = "|",
              },
              sections = {
                lualine_a = { "mode" },
                lualine_b = { "branch", "diff", "diagnostics" },
                lualine_c = { { "filename", path = 1 } },
                lualine_x = { "encoding", "fileformat", "filetype" },
                lualine_y = { "progress" },
                lualine_z = { "location" },
              },
            })
          end,
        },

        -- File tree
        {
          "nvim-tree/nvim-tree.lua",
          dependencies = { "nvim-tree/nvim-web-devicons" },
          config = function()
            require("nvim-tree").setup({
              view = { width = 30 },
              renderer = { group_empty = true },
              filters = { dotfiles = false },
            })
            vim.keymap.set("n", "<leader>e", ":NvimTreeToggle<CR>", { desc = "Toggle file tree", silent = true })
          end,
        },

        -- Git signs
        {
          "lewis6991/gitsigns.nvim",
          config = function()
            require("gitsigns").setup({
              signs = {
                add = { text = "+" },
                change = { text = "~" },
                delete = { text = "_" },
                topdelete = { text = "‾" },
                changedelete = { text = "~" },
              },
            })
          end,
        },

        -- Which-key
        {
          "folke/which-key.nvim",
          event = "VeryLazy",
          config = function()
            require("which-key").setup({})
          end,
        },

        -- Format on save
        {
          "stevearc/conform.nvim",
          event = "BufWritePre",
          config = function()
            require("conform").setup({
              formatters_by_ft = {
                nix = { "alejandra" },
                lua = { "stylua" },
                javascript = { "prettierd" },
                typescript = { "prettierd" },
                json = { "prettierd" },
                yaml = { "prettierd" },
                html = { "prettierd" },
                css = { "prettierd" },
                markdown = { "prettierd" },
                python = { "ruff_format" },
                go = { "gofmt" },
                rust = { "rustfmt" },
                sh = { "shfmt" },
                bash = { "shfmt" },
              },
              format_on_save = {
                timeout_ms = 2000,
                lsp_fallback = true,
              },
            })
          end,
        },

        -- Auto-pairs (brackets, quotes)
        {
          "windwp/nvim-autopairs",
          event = "InsertEnter",
          config = function()
            require("nvim-autopairs").setup({})
          end,
        },

        -- Comment (gcc / gc<motion>)
        {
          "numToStr/Comment.nvim",
          event = "VeryLazy",
          config = function()
            require("Comment").setup({})
          end,
        },

        -- Indent guides
        {
          "lukas-reineke/indent-blankline.nvim",
          main = "ibl",
          event = "BufReadPost",
          config = function()
            require("ibl").setup({
              indent = { char = "│" },
              scope = { enabled = true, show_start = false, show_end = false },
            })
          end,
        },
      }, {
        rocks = { enabled = false },  -- No luarocks needed, silences the warning
      })
    '';
  };
}
