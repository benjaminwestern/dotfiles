return {
  -- Detect tabstop and shiftwidth automatically
  'tpope/vim-sleuth',

  -- Web dev icons
  { 'nvim-tree/nvim-web-devicons' },

  -- Smart colorcolumn — only appears on lines that exceed the limit
  {
    'm4xshen/smartcolumn.nvim',
    opts = {
      -- Show column guide at 120 for most files
      colorcolumn = '120',
      -- Don't show for these filetypes (where line length doesn't matter)
      disabled_filetypes = {
        'text',
        'help',
        'gitcommit',
        'NeogitStatus',
      },
      -- Show at 80 for these specific filetypes if preferred
      custom_colorcolumn = {
        -- python = '88',   -- PEP 8 recommends 88
        -- go = '120',      -- Go is 120
      },
    },
  },
}
