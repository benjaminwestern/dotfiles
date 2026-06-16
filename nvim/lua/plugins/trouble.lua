-- =============================================================================
-- ||                                                                         ||
-- ||                         NVIM / PLUGIN / TROUBLE                         ||
-- ||                                                                         ||
-- =============================================================================
return {
  'folke/trouble.nvim',
  cmd = { 'Trouble' },
  keys = {
    {
      '<leader>q',
      '<cmd>Trouble diagnostics toggle<cr>',
      desc = '[Q]uickfix / Diagnostics (trouble)',
    },
    {
      '<leader>Q',
      '<cmd>Trouble diagnostics toggle filter.buf=0<cr>',
      desc = '[Q]uickfix / Diagnostics (current buffer only)',
    },
    {
      '<leader>cl',
      '<cmd>Trouble lsp toggle focus=false win.position=right<cr>',
      desc = '[C]ode [L]SP references / definitions (trouble)',
    },
    {
      '<leader>sq',
      '<cmd>Trouble quickfix toggle<cr>',
      desc = '[S]earch [Q]uickfix list (trouble)',
    },
    {
      ']q',
      function()
        require('trouble').next { skip_groups = true, jump = true }
      end,
      desc = 'Next trouble / diagnostic item',
    },
    {
      '[q',
      function()
        require('trouble').prev { skip_groups = true, jump = true }
      end,
      desc = 'Previous trouble / diagnostic item',
    },
  },
  opts = {
    auto_open = false,
    auto_close = false,
    auto_preview = true,
    auto_fold = false,
    auto_jump = false,
    focus = false,
    follow = true,
    indent_guides = true,
    max_items = 200,
    multiline = true,
    pinned = false,
    warn_no_results = true,
    open_no_results = false,
    modes = {
      diagnostics = {
        auto_open = false,
        auto_close = false,
        auto_preview = true,
        auto_jump = false,
        title = 'Diagnostics',
        filter = { severity = vim.diagnostic.severity.ERROR },
      },
    },
    icons = {
      indent = {
        top = '│ ',
        middle = '├╴',
        last = '└╴',
        fold_open = '▼',
        fold_closed = '▶',
        ws = '  ',
      },
      folder_closed = ' ',
      folder_open = ' ',
      kinds = {
        Array = '',
        Boolean = '󰨙',
        Class = '󰠱',
        Constant = '󰏿',
        Constructor = '',
        Enum = '󰕘',
        EnumMember = '',
        Event = '',
        Field = '󰜢',
        File = '󰈙',
        Function = '󰊕',
        Interface = '',
        Key = '󰌋',
        Method = '󰆧',
        Module = '',
        Namespace = '󰦮',
        Null = '',
        Number = '󰎠',
        Object = '',
        Operator = '󰆕',
        Package = '',
        Property = '󰖷',
        String = '󰀬',
        Struct = '󰙅',
        TypeParameter = '',
        Variable = '󰀫',
      },
    },
  },
}
