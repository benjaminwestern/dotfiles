return {
  -- Essential mini.nvim collection (base dependency)
  { 'echasnovski/mini.nvim', version = false },

  -- Simple and beautiful statusline
  {
    'echasnovski/mini.statusline',
    version = '*',
    opts = {
      use_icons = vim.g.have_nerd_font,
    },
  },

  -- Better Around/Inside textobjects (replaces nvim-treesitter-textobjects)
  -- Examples: va) - [V]isually select [A]round [)]paren, ci' - [C]hange [I]nside [']quote
  {
    'echasnovski/mini.ai',
    version = false,
    config = function()
      require('mini.ai').setup {
        -- Avoid conflicts with built-in incremental selection on Neovim>=0.12
        mappings = {
          around_next = 'aa',
          inside_next = 'ii',
        },
        n_lines = 500,
      }
    end,
  },

  -- Move lines and visual selections with Alt+arrow or Alt+h/j/k/l
  {
    'echasnovski/mini.move',
    version = false,
    config = function()
      require('mini.move').setup {
        mappings = {
          -- Normal mode
          left = '<M-h>',
          right = '<M-l>',
          down = '<M-j>',
          up = '<M-k>',
          -- Visual mode
          line_left = '<M-h>',
          line_right = '<M-l>',
          line_down = '<M-j>',
          line_up = '<M-k>',
        },
      }
    end,
  },

  -- Add/delete/change surrounding characters (replaces nvim-surround)
  -- saiw" - [S]urround [A]dd [I]nner [W]ord with "
  -- sd" - [S]urround [D]elete "
  -- sr"' - [S]urround [R]eplace " with '
  {
    'echasnovski/mini.surround',
    version = false,
    opts = {
      mappings = {
        add = 'sa',
        delete = 'sd',
        find = 'sf',
        find_left = 'sF',
        highlight = 'sh',
        replace = 'sr',
        update_n_lines = 'sn',
      },
    },
  },

  -- Auto-close brackets, quotes, and pairs (replaces nvim-autopairs)
  {
    'echasnovski/mini.pairs',
    version = false,
    opts = {},
  },

  -- Text operators: evaluate (g=), exchange (gx), multiply (gm), replace (gr), sort (gs)
  {
    'echasnovski/mini.operators',
    version = false,
    opts = {
      evaluate = { prefix = 'g=' },
      exchange = { prefix = 'gx' },
      multiply = { prefix = 'gm' },
      replace = { prefix = 'gr' },
      sort = { prefix = 'gs' },
    },
  },

  -- Highlight trailing whitespace in red; auto-trim on save
  {
    'echasnovski/mini.trailspace',
    version = false,
    config = function()
      require('mini.trailspace').setup()
      -- Auto-trim trailing spaces on save
      vim.api.nvim_create_autocmd('BufWritePre', {
        pattern = '*',
        callback = function()
          MiniTrailspace.trim()
        end,
      })
    end,
  },

  -- Delete buffers without closing their window (preserves layout)
  {
    'echasnovski/mini.bufremove',
    version = false,
    config = function()
      require('mini.bufremove').setup()
    end,
    keys = {
      { '<leader>bd', function() require('mini.bufremove').delete() end, desc = '[B]uffer [D]elete (keep window)' },
      { '<leader>bD', function() require('mini.bufremove').wipeout() end, desc = '[B]uffer [W]ipeout (keep window)' },
    },
  },
}
