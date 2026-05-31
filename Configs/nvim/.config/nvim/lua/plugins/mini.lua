-- =============================================================================
-- ||                                                                         ||
-- ||                          NVIM / PLUGIN / MINI                           ||
-- ||                                                                         ||
-- =============================================================================
return {
  -- Essential mini.nvim collection (base dependency)
  { 'echasnovski/mini.nvim', version = false },

  -- Compact statusline: mode, repo/branch, path, diagnostics, filetype, location.
  {
    'echasnovski/mini.statusline',
    version = '*',
    config = function()
      local repo_cache = {}

      local mode_map = {
        n = 'N',
        i = 'I',
        v = 'V',
        V = 'V-L',
        ['\22'] = 'V-B',
        c = 'C',
        R = 'R',
        t = 'T',
      }

      local function buf_path()
        local name = vim.api.nvim_buf_get_name(0)
        if name == '' then
          return '[No Name]'
        end
        return vim.fn.fnamemodify(name, ':~:.')
      end

      local function git_root()
        local name = vim.api.nvim_buf_get_name(0)
        local start = name ~= '' and vim.fs.dirname(name) or vim.fn.getcwd()
        if not start or start == '' then
          start = vim.fn.getcwd()
        end
        return vim.fs.root(start, '.git')
      end

      local function repo_name()
        local root = git_root()
        if not root then
          return ''
        end
        if repo_cache[root] then
          return repo_cache[root]
        end
        repo_cache[root] = vim.fn.fnamemodify(root, ':t')
        return repo_cache[root]
      end

      local function git_label()
        local repo = repo_name()
        if repo == '' then
          return ''
        end
        local branch = vim.b.gitsigns_head
        if branch and branch ~= '' then
          return repo .. ':' .. branch
        end
        return repo
      end

      local function diagnostics_label()
        local counts = vim.diagnostic.count(0)
        local errors = counts[vim.diagnostic.severity.ERROR] or 0
        local warnings = counts[vim.diagnostic.severity.WARN] or 0
        if errors == 0 and warnings == 0 then
          return ''
        end
        local parts = {}
        if errors > 0 then
          table.insert(parts, 'E' .. errors)
        end
        if warnings > 0 then
          table.insert(parts, 'W' .. warnings)
        end
        return table.concat(parts, ' ')
      end

      local function filetype_label()
        return vim.bo.filetype ~= '' and vim.bo.filetype or ''
      end

      require('mini.statusline').setup({
        use_icons = false,
        content = {
          active = function()
            local _, mode_hl = MiniStatusline.section_mode({ trunc_width = 120 })
            local mode = mode_map[vim.fn.mode()] or vim.fn.mode():upper()
            local path = buf_path()
            local modified = vim.bo.modified and '[+]' or ''
            local readonly = vim.bo.readonly and vim.bo.buftype == '' and '[RO]' or ''
            local repo = git_label()
            local diagnostics = diagnostics_label()
            local filetype = filetype_label()
            local location = vim.fn.line('.') .. ':' .. vim.fn.virtcol('.')

            return MiniStatusline.combine_groups({
              { hl = mode_hl, strings = { mode } },
              { hl = 'MiniStatuslineDevinfo', strings = { repo } },
              '%<',
              { hl = 'MiniStatuslineFilename', strings = { path, modified, readonly } },
              '%=',
              { hl = 'MiniStatuslineDevinfo', strings = { diagnostics } },
              { hl = 'MiniStatuslineFileinfo', strings = { filetype } },
              { hl = mode_hl, strings = { location } },
            })
          end,
          inactive = function()
            return MiniStatusline.combine_groups({
              { hl = 'MiniStatuslineInactive', strings = { buf_path() } },
            })
          end,
        },
      })
    end,
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
