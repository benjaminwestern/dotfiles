-- =============================================================================
-- ||                                                                         ||
-- ||                          NVIM / PLUGIN / LINT                           ||
-- ||                                                                         ||
-- =============================================================================
return {
  {
    -- Lightweight linting engine that runs linters asynchronously.
    -- Complements LSP diagnostics (LSPs do type checking; linters do style).
    'mfussenegger/nvim-lint',
    event = { 'BufReadPre', 'BufNewFile' },
    config = function()
      local lint = require 'lint'

      lint.linters_by_ft = {
        -- Bash / shell scripts
        sh = { 'shellcheck' },
        bash = { 'shellcheck' },
        zsh = { 'shellcheck' },
        -- Python (pyright handles types; flake8 catches style issues)
        python = { 'flake8' },
        -- JavaScript / TypeScript (eslint catches style issues not caught by ts_ls)
        javascript = { 'eslint' },
        typescript = { 'eslint' },
        javascriptreact = { 'eslint' },
        typescriptreact = { 'eslint' },
      }

      -- Run linter on write and on entering a buffer
      local lint_augroup = vim.api.nvim_create_augroup('lint', { clear = true })
      vim.api.nvim_create_autocmd({ 'BufEnter', 'BufWritePost', 'InsertLeave' }, {
        group = lint_augroup,
        callback = function()
          -- Only lint if the linter is available (avoid noisy errors)
          lint.try_lint()
        end,
      })
    end,
  },
}
