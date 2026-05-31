-- =============================================================================
-- ||                                                                         ||
-- ||                        NVIM / PLUGIN / TELESCOPE                        ||
-- ||                                                                         ||
-- =============================================================================
return {
  'nvim-telescope/telescope.nvim',
  branch = 'master',
  dependencies = {
    'nvim-lua/plenary.nvim',
    {
      'nvim-telescope/telescope-fzf-native.nvim',
      build = 'make',
      cond = function()
        return vim.fn.executable 'make' == 1
      end,
    },
    -- Makes vim.ui.select use telescope (nicer menus for LSP code actions, etc.)
    { 'nvim-telescope/telescope-ui-select.nvim' },
  },
  config = function()
    require('telescope').setup {
      defaults = {
        -- Start in insert mode for most pickers so you can immediately type
        initial_mode = 'insert',
        mappings = {
          i = {
            ['<C-u>'] = false,
            ['<C-d>'] = false,
            ['<C-j>'] = require('telescope.actions').move_selection_next,
            ['<C-k>'] = require('telescope.actions').move_selection_previous,
          },
          n = {
            ['<C-j>'] = require('telescope.actions').move_selection_next,
            ['<C-k>'] = require('telescope.actions').move_selection_previous,
          },
        },
        -- Sorting and matching tuned for speed and accuracy
        sorting_strategy = 'ascending',
        layout_strategy = 'horizontal',
        layout_config = {
          horizontal = {
            prompt_position = 'top',
            preview_width = 0.55,
            results_width = 0.8,
          },
          vertical = {
            mirror = false,
          },
          width = 0.87,
          height = 0.80,
          preview_cutoff = 120,
        },
      },
      pickers = {
        -- Buffers: sort by last used, show all buffers including current
        buffers = {
          sort_lastused = true,
          sort_mru = true,
          ignore_current_buffer = false,
          show_all_buffers = true,
          theme = 'dropdown',
          previewer = false,
          layout_config = {
            width = 0.5,
            height = 0.6,
          },
        },
        -- Find files: nice dropdown for quick file picking
        find_files = {
          theme = 'dropdown',
          previewer = false,
          hidden = true,
        },
        -- Oldfiles: dropdown for recent files
        oldfiles = {
          theme = 'dropdown',
          previewer = false,
        },
        -- Live grep: keep previewer for context
        live_grep = {
          theme = 'ivy',
        },
        -- Diagnostics: sort by severity, show line numbers, nice icons
        diagnostics = {
          theme = 'dropdown',
          previewer = false,
          layout_config = {
            width = 0.8,
            height = 0.6,
          },
          sort_by = 'severity',
          -- Show workspace diagnostics by default; buffer-only via <leader>sD
          bufnr = nil,
        },
      },
      extensions = {
        -- Use dropdown theme for all vim.ui.select calls
        ['ui-select'] = {
          require('telescope.themes').get_dropdown {
            -- even more opts
          },
        },
      },
    }

    -- Enable telescope extensions if they are installed
    pcall(require('telescope').load_extension, 'fzf')
    pcall(require('telescope').load_extension, 'ui-select')

    -- -----------------------------------------------------------------------------
    -- CORE NAVIGATION KEYMAPS
    -- -----------------------------------------------------------------------------

    local builtin = require 'telescope.builtin'

    -- -----------------------------------------------------------------------------
    -- DOUBLE-TAP SPACE = BUFFER SWITCHING
    -- -----------------------------------------------------------------------------
    -- This is your primary navigation mechanism. Hit space twice and
    -- you get a beautiful modal list of open buffers ordered by MRU.
    vim.keymap.set('n', '<leader><space>', function()
      builtin.buffers {
        sort_mru = true,
        sort_lastused = true,
        ignore_current_buffer = false,
        show_all_buffers = true,
      }
    end, { desc = '[ ] Switch between open buffers (MRU)' })

    -- -----------------------------------------------------------------------------
    -- FILE FINDING
    -- -----------------------------------------------------------------------------
    vim.keymap.set('n', '<leader>sf', builtin.find_files, { desc = '[S]earch [F]iles' })
    vim.keymap.set('n', '<leader>s.', builtin.oldfiles, { desc = '[S]earch Recent Files ("." for repeat)' })
    vim.keymap.set('n', '<leader>?', builtin.oldfiles, { desc = '[?] Find recently opened files' })
    vim.keymap.set('n', '<leader>gf', builtin.git_files, { desc = 'Search [G]it [F]iles' })
    vim.keymap.set('n', '<leader>gs', builtin.git_status, { desc = '[G]it [S]tatus (modified files)' })
    vim.keymap.set('n', '<leader>gh', function()
      local bufnr = vim.api.nvim_get_current_buf()
      -- Guard: only work in regular file buffers
      if vim.bo[bufnr].buftype ~= '' or vim.api.nvim_buf_get_name(bufnr) == '' then
        vim.notify('Not a file buffer', vim.log.levels.WARN)
        return
      end
      local filepath = vim.api.nvim_buf_get_name(bufnr)
      if vim.fn.isdirectory(filepath) == 1 then
        vim.notify('Directory buffers not supported', vim.log.levels.WARN)
        return
      end
      require('gitsigns').setqflist(0, {
        use_location_list = true,
        nr = 0,
        open = false,
      }, function()
        vim.schedule(function()
          builtin.loclist {
            prompt_title = 'Git Hunks in Current Buffer',
          }
        end)
      end)
    end, { desc = '[G]it [H]unks in current buffer (loclist)' })

    -- -----------------------------------------------------------------------------
    -- TEXT SEARCH
    -- -----------------------------------------------------------------------------
    vim.keymap.set('n', '<leader>/', function()
      builtin.current_buffer_fuzzy_find(require('telescope.themes').get_dropdown {
        winblend = 10,
        previewer = false,
      })
    end, { desc = '[/] Fuzzily search in current buffer' })

    vim.keymap.set('n', '<leader>sg', builtin.live_grep, { desc = '[S]earch by [G]rep' })
    vim.keymap.set('n', '<leader>sw', builtin.grep_string, { desc = '[S]earch current [W]ord' })

    -- -----------------------------------------------------------------------------
    -- OPEN FILES SEARCH
    -- -----------------------------------------------------------------------------
    local function telescope_live_grep_open_files()
      builtin.live_grep {
        grep_open_files = true,
        prompt_title = 'Live Grep in Open Files',
      }
    end
    vim.keymap.set('n', '<leader>s/', telescope_live_grep_open_files, { desc = '[S]earch [/] in Open Files' })

    -- -----------------------------------------------------------------------------
    -- PROJECT / DIRECTORY HOPPING
    -- -----------------------------------------------------------------------------

    -- Search files in a specific directory (prompted)
    vim.keymap.set('n', '<leader>sp', function()
      -- Pick a directory, then find files in it
      builtin.find_files {
        prompt_title = 'Find Files in Directory...',
        cwd = vim.fn.input('Directory: ', vim.fn.getcwd(), 'dir'),
        hidden = true,
      }
    end, { desc = '[S]earch in a [P]icked directory' })

    -- Grep in a specific directory (prompted)
    vim.keymap.set('n', '<leader>sP', function()
      builtin.live_grep {
        prompt_title = 'Live Grep in Directory...',
        cwd = vim.fn.input('Directory: ', vim.fn.getcwd(), 'dir'),
      }
    end, { desc = '[S]earch by [G]rep in picked directory' })

    -- Find files in the same directory as the current file
    vim.keymap.set('n', '<leader>s,', function()
      local current_file = vim.api.nvim_buf_get_name(0)
      if current_file == '' then
        print 'No file in current buffer'
        return
      end
      local current_dir = vim.fn.fnamemodify(current_file, ':h')
      builtin.find_files {
        prompt_title = 'Files in ' .. current_dir,
        cwd = current_dir,
        hidden = true,
      }
    end, { desc = "[S]earch files in current file's directory" })

    -- Live grep in the same directory as the current file
    vim.keymap.set('n', '<leader>s<', function()
      local current_file = vim.api.nvim_buf_get_name(0)
      if current_file == '' then
        print 'No file in current buffer'
        return
      end
      local current_dir = vim.fn.fnamemodify(current_file, ':h')
      builtin.live_grep {
        prompt_title = 'Grep in ' .. current_dir,
        cwd = current_dir,
      }
    end, { desc = "[S]earch grep in current file's directory" })

    -- -----------------------------------------------------------------------------
    -- GIT ROOT SEARCH
    -- -----------------------------------------------------------------------------
    -- Function to find the git root directory based on the current buffer's path
    local function find_git_root()
      local current_file = vim.api.nvim_buf_get_name(0)
      local current_dir
      local cwd = vim.fn.getcwd()
      if current_file == '' then
        current_dir = cwd
      else
        current_dir = vim.fn.fnamemodify(current_file, ':h')
      end
      local git_root = vim.fn.systemlist('git -C ' .. vim.fn.escape(current_dir, ' ') .. ' rev-parse --show-toplevel')[1]
      if vim.v.shell_error ~= 0 then
        print 'Not a git repository. Searching on current working directory'
        return cwd
      end
      return git_root
    end

    local function live_grep_git_root()
      local git_root = find_git_root()
      if git_root then
        builtin.live_grep {
          search_dirs = { git_root },
        }
      end
    end
    vim.api.nvim_create_user_command('LiveGrepGitRoot', live_grep_git_root, {})
    vim.keymap.set('n', '<leader>sG', ':LiveGrepGitRoot<cr>', { desc = '[S]earch by [G]rep on Git Root' })

    -- -----------------------------------------------------------------------------
    -- LSP / DIAGNOSTIC SEARCH
    -- -----------------------------------------------------------------------------

    -- Workspace diagnostics (all open buffers + project files LSP knows about)
    vim.keymap.set('n', '<leader>sd', function()
      builtin.diagnostics {
        severity_sort = true,
        sort_by = 'severity',
      }
    end, { desc = '[S]earch [D]iagnostics (workspace)' })

    -- Current buffer only diagnostics
    vim.keymap.set('n', '<leader>sD', function()
      builtin.diagnostics {
        bufnr = 0,
        severity_sort = true,
        sort_by = 'severity',
      }
    end, { desc = '[S]earch [D]iagnostics (current buffer only)' })

    vim.keymap.set('n', '<leader>sr', builtin.resume, { desc = '[S]earch [R]esume' })
    vim.keymap.set('n', '<leader>ss', builtin.builtin, { desc = '[S]earch [S]elect Telescope' })
    vim.keymap.set('n', '<leader>sH', builtin.help_tags, { desc = '[S]earch [H]elp' })
    vim.keymap.set('n', '<leader>sk', builtin.keymaps, { desc = '[S]earch [K]eymaps' })
    vim.keymap.set('n', '<leader>sc', builtin.commands, { desc = '[S]earch [C]ommands' })

    -- Shortcut for searching your Neovim configuration files
    vim.keymap.set('n', '<leader>sn', function()
      builtin.find_files { cwd = vim.fn.stdpath 'config' }
    end, { desc = '[S]earch [N]eovim files' })

    -- -----------------------------------------------------------------------------
    -- CHANGE DIRECTORY / PROJECT HOPPING
    -- -----------------------------------------------------------------------------

    -- Quick cd to a directory with tab completion, then optionally search
    vim.keymap.set('n', '<leader>cd', function()
      local dir = vim.fn.input('Change directory to: ', vim.fn.getcwd(), 'dir')
      if dir and dir ~= '' then
        vim.cmd('cd ' .. vim.fn.fnameescape(dir))
        print('Changed directory to: ' .. dir)
      end
    end, { desc = '[C]hange [D]irectory' })

    -- Change directory to current file's directory
    vim.keymap.set('n', '<leader>cD', function()
      local current_file = vim.api.nvim_buf_get_name(0)
      if current_file == '' then
        print 'No file in current buffer'
        return
      end
      local dir = vim.fn.fnamemodify(current_file, ':h')
      vim.cmd('cd ' .. vim.fn.fnameescape(dir))
      print('Changed directory to: ' .. dir)
    end, { desc = '[C]hange [D]irectory to file location' })

    -- -----------------------------------------------------------------------------
    -- LSP PICKERS (buffer-local, set up via autocmd in lsp.lua)
    -- -----------------------------------------------------------------------------
    -- These are handled in lsp.lua's LspAttach autocmd to ensure they
    -- only exist when an LSP is active.
  end,
}
