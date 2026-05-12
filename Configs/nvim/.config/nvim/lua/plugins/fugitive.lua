return {
  'kdheepak/lazygit.nvim',
  cmd = {
    'LazyGit',
    'LazyGitConfig',
    'LazyGitCurrentFile',
    'LazyGitFilter',
    'LazyGitFilterCurrentFile',
  },
  -- Optional: floating window border style
  dependencies = {
    'nvim-lua/plenary.nvim',
  },
  keys = {
    { '<leader>gg', '<cmd>LazyGit<cr>', desc = '[G]it — open lazygit (floating)' },
    { '<leader>gl', '<cmd>LazyGitCurrentFile<cr>', desc = '[G]it — lazygit [l]og for current file' },
  },
}
