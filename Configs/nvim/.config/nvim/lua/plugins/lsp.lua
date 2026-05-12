return {
  {
    -- `lazydev` configures Lua LSP for your Neovim config, runtime and plugins
    -- used for completion, annotations and signatures of Neovim apis
    'folke/lazydev.nvim',
    ft = 'lua',
    opts = {
      library = {
        -- Load luvit types when the `vim.uv` word is found
        { path = '${3rd}/luv/library', words = { 'vim%.uv' } },
      },
    },
  },
  {
    -- LSP Configuration & Plugins
    'neovim/nvim-lspconfig',
    event = { 'BufReadPre', 'BufNewFile' },
    dependencies = {
      -- Automatically install LSPs to stdpath for neovim
      { 'mason-org/mason.nvim', config = true, cmd = { 'Mason', 'MasonInstall', 'MasonUpdate', 'MasonUninstall' } },
      'mason-org/mason-lspconfig.nvim',

      -- Useful status updates for LSP
      -- NOTE: `opts = {}` is the same as calling `require('fidget').setup({})`
      { 'j-hui/fidget.nvim',       opts = {} },

      -- lazydev needs to be setup before lspconfig
      'folke/lazydev.nvim',
    },
    config = function()
      -- mason-lspconfig requires that these setup functions are called in this order
      -- before setting up the servers.
      require('mason').setup()
      require('mason-lspconfig').setup()

      -- blink.cmp supports additional completion capabilities, so broadcast that to servers
      local capabilities = vim.lsp.protocol.make_client_capabilities()
      capabilities = require('blink.cmp').get_lsp_capabilities(capabilities)

      -- [[ Global LSP Attach Keymaps ]]
      -- Neovim 0.10+ provides a native LspAttach event. We use this instead of
      -- per-server on_attach callbacks.
      vim.api.nvim_create_autocmd('LspAttach', {
        group = vim.api.nvim_create_augroup('user-lsp-attach', { clear = true }),
        callback = function(event)
          local bufnr = event.buf
          local nmap = function(keys, func, desc)
            vim.keymap.set('n', keys, func, { buffer = bufnr, desc = 'LSP: ' .. desc })
          end

          nmap('<leader>ca', function()
            vim.lsp.buf.code_action { context = { only = { 'quickfix', 'refactor', 'source' }, diagnostics = {} } }
          end, '[C]ode [A]ction')

          -- Remove default gr mapping to avoid conflicts
          pcall(vim.keymap.del, 'n', 'gr', { buffer = bufnr })

          nmap('gd', require('telescope.builtin').lsp_definitions, '[G]oto [D]efinition')
          nmap('gr', function()
            require('telescope.builtin').lsp_references()
          end, '[G]oto [R]eferences')
          nmap('gI', require('telescope.builtin').lsp_implementations, '[G]oto [I]mplementation')
          nmap('<leader>D', require('telescope.builtin').lsp_type_definitions, 'Type [D]efinition')
          nmap('<leader>ds', require('telescope.builtin').lsp_document_symbols, '[D]ocument [S]ymbols')
          nmap('<leader>ws', require('telescope.builtin').lsp_dynamic_workspace_symbols, '[W]orkspace [S]ymbols')

          nmap('K', vim.lsp.buf.hover, 'Hover Documentation')
          nmap('<C-k>', vim.lsp.buf.signature_help, 'Signature Documentation')
          nmap('gD', vim.lsp.buf.declaration, '[G]oto [D]eclaration')

          -- Rename the variable under your cursor (works across files)
          nmap('grn', vim.lsp.buf.rename, '[R]e[n]ame symbol')

          -- Create a command `:Format` local to the LSP buffer
          vim.api.nvim_buf_create_user_command(bufnr, 'Format', function(_)
            vim.lsp.buf.format()
          end, { desc = 'Format current buffer with LSP' })

          -- Document highlight: highlight all references when cursor rests
          local client = vim.lsp.get_client_by_id(event.data.client_id)
          if client and client:supports_method('textDocument/documentHighlight', bufnr) then
            local highlight_augroup = vim.api.nvim_create_augroup('user-lsp-highlight', { clear = false })
            vim.api.nvim_create_autocmd({ 'CursorHold', 'CursorHoldI' }, {
              buffer = bufnr,
              group = highlight_augroup,
              callback = vim.lsp.buf.document_highlight,
            })
            vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
              buffer = bufnr,
              group = highlight_augroup,
              callback = vim.lsp.buf.clear_references,
            })
            vim.api.nvim_create_autocmd('LspDetach', {
              group = vim.api.nvim_create_augroup('user-lsp-detach', { clear = true }),
              callback = function(event2)
                vim.lsp.buf.clear_references()
                vim.api.nvim_clear_autocmds { group = 'user-lsp-highlight', buffer = event2.buf }
              end,
            })
          end

          -- Toggle inlay hints (Rust/TypeScript show types inline)
          if client and client:supports_method('textDocument/inlayHint', bufnr) then
            nmap('<leader>th', function()
              vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled { bufnr = bufnr })
            end, '[T]oggle Inlay [H]ints')
          end
        end,
      })

      -- [[ Server Configurations ]]
      -- Using vim.lsp.config (Neovim 0.11+ native API) instead of the
      -- deprecated lspconfig.setup() framework.
      local servers = {
        -- Terraform
        terraformls = {},

        -- SQL
        sqls = {},

        -- Go
        gopls = {},

        -- Python
        pyright = {},

        -- JavaScript/TypeScript
        ts_ls = {},

        -- HTML
        html = { filetypes = { 'html', 'twig', 'hbs' } },

        -- CSS / SCSS
        cssls = {},

        -- JSON
        jsonls = {},

        -- YAML
        yamlls = {},

        -- Markdown
        marksman = {},

        -- Bash / Shell
        bashls = {},

        -- Rust
        rust_analyzer = {},

        -- Zig
        zls = {},

        -- Lua
        lua_ls = {
          settings = {
            Lua = {
              workspace = {
                checkThirdParty = false,
              },
              telemetry = { enable = false },
            },
          },
        },
      }

      for name, server in pairs(servers) do
        -- Merge capabilities into each server config
        local config = vim.tbl_deep_extend('force', server, { capabilities = capabilities })
        vim.lsp.config(name, config)
        vim.lsp.enable(name)
      end

      -- Swift: sourcekit-lsp is not available in Mason (it ships with Xcode).
      -- If `sourcekit-lsp` is on PATH, set it up manually.
      if vim.fn.executable 'sourcekit-lsp' == 1 then
        vim.lsp.config('sourcekit', { capabilities = capabilities })
        vim.lsp.enable('sourcekit')
      end

      -- Ensure the servers are available for installation via Mason
      require('mason-lspconfig').setup {
        ensure_installed = vim.tbl_keys(servers),
        automatic_installation = false,
      }

      -- [[ Diagnostic keymaps ]]
      vim.keymap.set('n', '[d', function() vim.diagnostic.jump({ count = -1, float = true }) end, { desc = 'Go to previous diagnostic message' })
      vim.keymap.set('n', ']d', function() vim.diagnostic.jump({ count = 1, float = true }) end, { desc = 'Go to next diagnostic message' })
      vim.keymap.set('n', '<leader>df', vim.diagnostic.open_float, { desc = '[D]iagnostic [F]loating message' })
      -- NOTE: <leader>q is handled by trouble.nvim for a beautiful diagnostics panel
    end
  },
}