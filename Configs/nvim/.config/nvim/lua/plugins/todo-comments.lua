return {
  -- Highlight and search TODO, FIXME, HACK, NOTE, BUG in comments
  'folke/todo-comments.nvim',
  event = { 'BufReadPost', 'BufNewFile' },
  dependencies = { 'nvim-lua/plenary.nvim' },
  opts = {
    signs = true, -- show icons in gutter
    sign_priority = 8,
    keywords = {
      FIX = {
        icon = ' ',
        color = 'error',
        alt = { 'FIXME', 'BUG', 'FIXIT', 'ISSUE' },
      },
      TODO = { icon = ' ', color = 'info' },
      HACK = { icon = ' ', color = 'warning' },
      WARN = { icon = ' ', color = 'warning', alt = { 'WARNING', 'XXX' } },
      PERF = { icon = ' ', alt = { 'OPTIM', 'PERFORMANCE', 'OPTIMIZE' } },
      NOTE = { icon = ' ', color = 'hint', alt = { 'INFO' } },
      TEST = { icon = '⏲ ', color = 'test', alt = { 'TESTING', 'PASSED', 'FAILED' } },
    },
    gui_style = {
      fg = 'NONE',
      bg = 'BOLD',
    },
    merge_keywords = true,
    highlight = {
      multiline = true,
      multiline_pattern = '^.',
      multiline_context = 10,
      before = '',
      keyword = 'wide',
      after = 'fg',
      pattern = [[.*<(KEYWORDS)\s*:]],
      comments_only = true,
      max_line_len = 400,
      exclude = {},
    },
    colors = {
      error = { 'DiagnosticError', 'ErrorMsg', '#DC2626' },
      warning = { 'DiagnosticWarn', 'WarningMsg', '#FBBF24' },
      info = { 'DiagnosticInfo', '#2563EB' },
      hint = { 'DiagnosticHint', '#10B981' },
      default = { 'Identifier', '#7C3AED' },
      test = { 'Identifier', '#FF00FF' },
    },
    search = {
      command = 'rg',
      args = {
        '--color=never',
        '--no-heading',
        '--with-filename',
        '--line-number',
        '--column',
      },
      pattern = [[\b(KEYWORDS):]],
    },
  },
  keys = {
    { '<leader>st', '<cmd>TodoTelescope<cr>', desc = '[S]earch [T]ODOs' },
    { '<leader>sT', '<cmd>TodoTelescope keywords=TODO,FIX,FIXME<cr>', desc = '[S]earch TODOs + FIXes' },
    { ']t', function() require('todo-comments').jump_next() end, desc = 'Next [t]odo comment' },
    { '[t', function() require('todo-comments').jump_prev() end, desc = 'Previous [t]odo comment' },
  },
}
