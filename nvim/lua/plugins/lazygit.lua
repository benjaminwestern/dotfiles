-- =============================================================================
-- ||                                                                         ||
-- ||                        NVIM / PLUGIN / LAZYGIT                        ||
-- =============================================================================
return {
  'kdheepak/lazygit.nvim',
  dependencies = { 'nvim-lua/plenary.nvim' },
  cmd = { 'LazyGit', 'LazyGitCurrentFile', 'LazyGitFilter', 'LazyGitFilterCurrentFile' },
  keys = {
    { '<leader>gs', '<cmd>LazyGit<cr>', desc = '[G]it [S]tatus (lazygit)' },
  },
}
