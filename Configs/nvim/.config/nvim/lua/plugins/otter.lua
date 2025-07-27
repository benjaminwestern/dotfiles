return {
  {
    -- LSP for embedded languages in code blocks (useful for mise files)
    'jmbuhr/otter.nvim',
    ft = { 'toml' },
    dependencies = {
      'nvim-treesitter/nvim-treesitter',
    },
    opts = {
      lsp = {
        hover = {
          border = 'rounded',
        },
      },
      buffers = {
        set_filetype = true,
        write_to_disk = false,
      },
      strip_wrapping_quote_characters = { '"', "'", '`' },
    },
    config = function(_, opts)
      local otter = require('otter')
      otter.setup(opts)

      -- Auto-activate otter for mise files
      vim.api.nvim_create_autocmd({ 'BufEnter', 'BufWritePost' }, {
        pattern = { '*mise*', '*.mise.*', '.mise.toml', 'mise.toml' },
        callback = function()
          local bufnr = vim.api.nvim_get_current_buf()
          local filename = vim.api.nvim_buf_get_name(bufnr)
          
          -- Only activate for mise-related TOML files
          if filename:match('%.toml$') and filename:match('mise') then
            otter.activate({ 'bash', 'sh', 'python', 'javascript', 'typescript' }, true, true)
          end
        end,
      })

      -- Keymaps for otter functionality
      vim.keymap.set('n', '<leader>oa', function()
        otter.activate({ 'bash', 'sh', 'python', 'javascript', 'typescript' }, true, true)
      end, { desc = '[O]tter [A]ctivate' })

      vim.keymap.set('n', '<leader>od', otter.deactivate, { desc = '[O]tter [D]eactivate' })
    end,
  },
}