-- =============================================================================
-- ||                                                                         ||
-- ||                        NVIM / PLUGIN / WHICH KEY                        ||
-- ||                                                                         ||
-- =============================================================================
return {
  {
    'folke/which-key.nvim',
    event = 'VeryLazy',
    opts = {
      -- Show immediately when you hit a prefix key
      delay = 0,
      win = {
        -- Make the popup wide enough to read the descriptions
        width = { min = 30, max = 60 },
        height = { min = 4, max = 25 },
        border = 'rounded',
        padding = { 1, 2, 1, 2 },
      },
      layout = {
        -- Show groups at the top, then individual keys
        height = { min = 4, max = 25 },
        spacing = 3,
        align = 'left',
      },
      -- Disable which-key's AUTO icon detection (it adds 📁 for "explorer", etc.)
      -- We keep our own custom emojis in the group strings below.
      icons = {
        rules = false,
        group = '',
        separator = '→',
      },
      -- Document existing key chains with verbose, educational labels
      spec = {
        -- -----------------------------------------------------------------------------
        -- CORE NAVIGATION (your daily bread)
        -- -----------------------------------------------------------------------------
        {
          '<leader><Space>',
          desc = '📋 Switch buffers (MRU order) — double-tap Space',
        },

        -- -----------------------------------------------------------------------------
        -- SEARCH / TELESCOPE (finding things)
        -- -----------------------------------------------------------------------------
        {
          '<leader>s',
          group = '🔍 Search / Find',
          mode = { 'n', 'v' },
        },
        {
          '<leader>sf',
          desc = 'Find files by name (fuzzy) — start typing filename',
        },
        {
          '<leader>sg',
          desc = 'Live grep — search text across project (powerful!)',
        },
        {
          '<leader>gf',
          desc = 'Search git tracked files only (not .gitignored)',
        },
        {
          '<leader>sw',
          desc = 'Search word under cursor across project',
        },
        {
          '<leader>s.',
          desc = 'Recent files — files you edited recently',
        },
        {
          '<leader>s/',
          desc = 'Grep in open files only',
        },
        {
          '<leader>sp',
          desc = 'Pick a directory, then find files in it',
        },
        {
          '<leader>sP',
          desc = 'Pick a directory, then grep in it',
        },
        {
          '<leader>s,',
          desc = "Find files in THIS file's directory",
        },
        {
          '<leader>s<',
          desc = "Grep in THIS file's directory",
        },
        {
          '<leader>sG',
          desc = 'Grep from git root (entire repo)',
        },
        {
          '<leader>sd',
          desc = 'Diagnostics (errors/warnings) — ALL open files + project',
        },
        {
          '<leader>sD',
          desc = 'Diagnostics — CURRENT buffer only',
        },
        {
          '<leader>sH',
          desc = 'Search help docs (:help topics)',
        },
        {
          '<leader>sk',
          desc = 'Search all keymaps (find what a key does)',
        },
        {
          '<leader>sc',
          desc = 'Search commands (:command list)',
        },
        {
          '<leader>sr',
          desc = 'Resume last search (continue where you left off)',
        },
        {
          '<leader>ss',
          desc = 'List all Telescope pickers',
        },
        {
          '<leader>sn',
          desc = 'Search your Neovim config files',
        },
        {
          '<leader>st',
          desc = 'Search TODO / FIXME / HACK / NOTE comments in project',
        },
        {
          '<leader>/',
          desc = 'Fuzzy search in current buffer only',
        },

        -- -----------------------------------------------------------------------------
        -- LSP (code intelligence) — press g to see all
        -- -----------------------------------------------------------------------------
        {
          'g',
          group = 'Go to / LSP',
        },
        {
          'gd',
          desc = 'Go to definition — jump to where this is defined',
        },
        {
          'gr',
          desc = 'Find references — who uses this? (Telescope list)',
        },
        {
          'gI',
          desc = 'Go to implementation — for interfaces/abstract methods',
        },
        {
          'gD',
          desc = 'Go to declaration (vs definition, for C/C++)',
        },
        {
          'grn',
          desc = 'Rename symbol — rename variable/function across project',
        },
        {
          'gcc',
          desc = 'Comment / uncomment current line (toggle)',
        },
        {
          'gc',
          desc = 'Comment / uncomment with motion (e.g. gcip = comment paragraph)',
          mode = { 'n', 'v' },
        },
        {
          'gb',
          desc = 'Block comment with motion (e.g. gbip = block comment paragraph)',
          mode = { 'n', 'v' },
        },
        {
          'gf',
          desc = 'Go to file under cursor',
        },
        {
          'gg',
          desc = 'Go to first line of file',
        },
        {
          'ge',
          desc = 'Go to end of previous word (backwards)',
        },
        {
          'gi',
          desc = 'Go to last insert position and enter insert mode',
        },
        {
          'gv',
          desc = 'Reselect last visual selection',
        },
        {
          'gx',
          desc = 'Exchange text (operator: gxiw = swap inner words) OR open URL if no motion',
        },
        {
          'g%',
          desc = 'Cycle backwards through matching brackets',
        },
        {
          'g=',
          desc = 'Evaluate expression (operator: g=iw = evaluate inner word)',
        },
        {
          'gm',
          desc = 'Multiply text (operator: gmiw = duplicate inner word)',
        },
        {
          'gr',
          desc = 'Replace with register (operator: griw = replace inner word from register)',
        },
        {
          'gs',
          desc = 'Sort text (operator: gsip = sort inner paragraph alphabetically)',
        },
        {
          'K',
          desc = 'Hover docs — show type/docs in floating window',
        },
        {
          '<leader>k',
          desc = 'Signature help — function parameters while typing',
        },
        {
          '<leader>D',
          desc = 'Type definition — what TYPE is this variable?',
        },
        {
          '<leader>ds',
          desc = 'Document symbols — list of functions/vars in this file',
        },
        {
          '<leader>w',
          group = '🌐 Workspace',
        },
        {
          '<leader>ws',
          desc = 'Workspace symbols — search symbols across project',
        },
        {
          '<leader>ca',
          desc = 'Code action — quick fixes, imports, refactors (context menu)',
        },
        {
          '<leader>f',
          desc = 'Format buffer — auto-prettify entire file',
        },

        -- -----------------------------------------------------------------------------
        -- DEBUG (DAP debugger)
        -- -----------------------------------------------------------------------------
        {
          '<leader>d',
          group = '🐛 Debug / Diagnostics',
        },
        {
          '<leader>dc',
          desc = 'Debug: Start / Continue execution',
        },
        {
          '<leader>dt',
          desc = 'Debug: Terminate session',
        },
        {
          '<leader>di',
          desc = 'Debug: Step INTO function call',
        },
        {
          '<leader>do',
          desc = 'Debug: Step OVER (skip into, go to next line)',
        },
        {
          '<leader>dO',
          desc = 'Debug: Step OUT of current function',
        },
        {
          '<leader>db',
          desc = 'Debug: Toggle breakpoint on this line',
        },
        {
          '<leader>dB',
          desc = 'Debug: Set CONDITIONAL breakpoint (e.g. i > 5)',
        },
        {
          '<leader>dl',
          desc = 'Debug: Set LOG point (prints without stopping)',
        },
        {
          '<leader>du',
          desc = 'Debug: Toggle debug UI (scopes, stack, watches)',
        },
        {
          '<leader>dr',
          desc = 'Debug: Toggle REPL (interactive eval)',
        },
        {
          '<leader>dL',
          desc = 'Debug: Re-run last debug session',
        },
        {
          '<leader>df',
          desc = 'Show diagnostic float (error under cursor)',
        },
        {
          '<leader>q',
          desc = 'Diagnostics panel — beautiful tree view (trouble)',
        },
        {
          '<leader>Q',
          desc = 'Diagnostics panel — current buffer only (trouble)',
        },
        {
          '<leader>cl',
          desc = 'LSP references / definitions tree (trouble)',
        },
        {
          '<leader>sq',
          desc = 'Quickfix list — beautiful tree view (trouble)',
        },

        -- -----------------------------------------------------------------------------
        -- NOTIFICATIONS (nvim-notify)
        -- -----------------------------------------------------------------------------
        {
          '<leader>u',
          group = '🔔 Notifications',
        },
        {
          '<leader>un',
          desc = 'Notification history — show past toasts',
        },
        {
          '<leader>uN',
          desc = 'Dismiss all notifications',
        },

        -- -----------------------------------------------------------------------------
        -- OPEN / EXTERNAL (macOS integration)
        -- -----------------------------------------------------------------------------
        {
          '<leader>o',
          group = '🚀 Open / External',
        },
        {
          '<leader>oo',
          desc = 'Open file in default macOS app (images, PDFs, etc)',
        },
        {
          '<leader>of',
          desc = 'Reveal file in Finder (selects the file)',
        },
        {
          '<leader>oF',
          desc = "Open file's directory in Finder",
        },
        {
          '<leader>om',
          desc = 'Open Markdown preview in browser',
        },
        {
          '<leader>oa',
          desc = 'Otter activate — embedded code blocks in TOML',
        },
        {
          '<leader>od',
          desc = 'Otter deactivate',
        },

        -- -----------------------------------------------------------------------------
        -- CHANGE / NAVIGATE DIRECTORIES
        -- -----------------------------------------------------------------------------
        {
          '<leader>c',
          group = '📁 Change Directory',
        },
        {
          '<leader>cd',
          desc = 'Change cwd — type or tab-complete a path',
        },
        {
          '<leader>cD',
          desc = "Change cwd to THIS file's directory",
        },

        -- -----------------------------------------------------------------------------
        -- INDENT / FORMAT
        -- -----------------------------------------------------------------------------
        {
          '<leader>=',
          desc = 'Auto-indent ENTIRE file (respects syntax)',
        },
        {
          '<leader>>',
          desc = 'Shift entire file RIGHT by one indent',
        },
        {
          '<leader><',
          desc = 'Shift entire file LEFT by one indent',
        },

        -- -----------------------------------------------------------------------------
        -- CLIPBOARD
        -- -----------------------------------------------------------------------------
        {
          '<leader>p',
          desc = 'Paste from SYSTEM clipboard',
        },
        {
          '<leader>P',
          desc = 'Paste BEFORE cursor from system clipboard',
        },

        -- -----------------------------------------------------------------------------
        -- GIT (gitsigns)
        -- -----------------------------------------------------------------------------
        {
          '<leader>h',
          group = '🌿 Git Hunk',
          mode = { 'n', 'v' },
        },
        {
          '<leader>hs',
          desc = 'Stage this hunk',
        },
        {
          '<leader>hr',
          desc = 'Reset (undo) this hunk',
        },
        {
          '<leader>hS',
          desc = 'Stage entire buffer',
        },
        {
          '<leader>hR',
          desc = 'Reset entire buffer (discard all changes)',
        },
        {
          '<leader>hu',
          desc = 'Undo stage hunk (unstage)',
        },
        {
          '<leader>hp',
          desc = 'Preview this hunk',
        },
        {
          '<leader>hb',
          desc = 'Blame line — who wrote this?',
        },
        {
          '<leader>hd',
          desc = 'Diff this file against index',
        },
        {
          '<leader>hD',
          desc = 'Diff this file against last commit',
        },
        {
          '<leader>hp',
          desc = 'Preview this hunk (see the diff)',
        },
        {
          '<leader>hb',
          desc = 'Blame line — who wrote this?',
        },
        {
          '<leader>hd',
          desc = 'Diff this file against index',
        },
        {
          '<leader>hD',
          desc = 'Diff this file against last commit',
        },
        {
          '<leader>tb',
          desc = 'Toggle git blame overlay (show author on each line)',
        },
        {
          '<leader>tD',
          desc = 'Toggle deleted lines highlight',
        },

        -- -----------------------------------------------------------------------------
        -- GIT STATUS
        -- -----------------------------------------------------------------------------
        {
          '<leader>g',
          group = '🔀 Git',
        },
        {
          '<leader>gs',
          desc = 'Git status PICKER — fuzzy search modified files',
        },
        {
          '<leader>gh',
          desc = 'Git [H]unks picker — ALL hunks in current buffer (jump to add/change/delete)',
        },

        -- -----------------------------------------------------------------------------
        -- BUFFER MANAGEMENT
        -- -----------------------------------------------------------------------------
        {
          '<leader>b',
          group = '📋 Buffer Management',
        },
        {
          '<leader>bd',
          desc = 'Delete buffer — keeps window open (smart)',
        },
        {
          '<leader>bD',
          desc = 'Wipeout buffer — keeps window open (force)',
        },

        -- -----------------------------------------------------------------------------
        -- TOGGLES (settings)
        -- -----------------------------------------------------------------------------
        {
          '<leader>t',
          group = '⚙️ Toggle Settings',
        },
        {
          '<leader>th',
          desc = 'Toggle LSP inlay hints (Rust/TypeScript type annotations)',
        },

        -- -----------------------------------------------------------------------------
        -- VIM NATIVE PREFIXES (comprehensive reference)
        -- -----------------------------------------------------------------------------
        {
          'z',
          group = 'Fold / Scroll / Spell',
        },
        {
          'zo',
          desc = 'Open fold under cursor',
        },
        {
          'zc',
          desc = 'Close fold under cursor',
        },
        {
          'za',
          desc = 'Toggle fold under cursor',
        },
        {
          'zR',
          desc = 'Open ALL folds in file',
        },
        {
          'zM',
          desc = 'Close ALL folds in file',
        },
        {
          'zt',
          desc = 'Scroll so cursor is at TOP of screen',
        },
        {
          'zz',
          desc = 'Scroll so cursor is at CENTER of screen',
        },
        {
          'zb',
          desc = 'Scroll so cursor is at BOTTOM of screen',
        },
        {
          'zs',
          desc = 'Enable spell checking',
        },
        {
          ']',
          group = 'Next / Forward',
        },
        {
          ']d',
          desc = 'Next diagnostic (error/warning)',
        },
        {
          ']c',
          desc = 'Next git [c]hange / hunk (added/changed/deleted)',
        },
        {
          ']]',
          desc = 'Next function / method / section',
        },
        {
          ']t',
          desc = 'Next TODO / FIXME / HACK / NOTE comment',
        },
        {
          '[',
          group = 'Previous / Backward',
        },
        {
          '[d',
          desc = 'Previous diagnostic (error/warning)',
        },
        {
          '[c',
          desc = 'Previous git [c]hange / hunk (added/changed/deleted)',
        },
        {
          '[[',
          desc = 'Previous function / method / section',
        },
        {
          '[t',
          desc = 'Previous TODO / FIXME / HACK / NOTE comment',
        },
        {
          'y',
          group = 'Yank (copy) — goes to system clipboard',
        },
        {
          'yy',
          desc = 'Yank entire line',
        },
        {
          'yip',
          desc = 'Yank inner paragraph',
        },
        {
          'yiw',
          desc = 'Yank inner word',
        },
        {
          'd',
          group = 'Delete — stays in internal registers',
        },
        {
          'dd',
          desc = 'Delete entire line',
        },
        {
          'dip',
          desc = 'Delete inner paragraph',
        },
        {
          'diw',
          desc = 'Delete inner word',
        },
        {
          'c',
          group = 'Change (delete + insert)',
        },
        {
          'cc',
          desc = 'Change entire line',
        },
        {
          'ciw',
          desc = 'Change inner word',
        },
        {
          'v',
          group = 'Visual mode',
        },
        {
          'V',
          desc = 'Visual line mode (select whole lines)',
        },
        {
          '<C-v>',
          desc = 'Visual block mode (select column)',
          mode = { 'n' },
        },
        {
          '<C-w>',
          group = 'Window management',
        },
        {
          '<C-w>h',
          desc = 'Move cursor to LEFT window',
        },
        {
          '<C-w>j',
          desc = 'Move cursor to BOTTOM window',
        },
        {
          '<C-w>k',
          desc = 'Move cursor to TOP window',
        },
        {
          '<C-w>l',
          desc = 'Move cursor to RIGHT window',
        },
        {
          '<C-w>s',
          desc = 'Split window HORIZONTALLY',
        },
        {
          '<C-w>v',
          desc = 'Split window VERTICALLY',
        },
        {
          '<C-w>q',
          desc = 'Close current window',
        },
        {
          '<C-w>o',
          desc = 'Close ALL other windows (keep only this one)',
        },
      },
    },
    keys = {
      {
        '<leader>??',
        function()
          require('which-key').show { global = true }
        end,
        desc = 'Show ALL keymaps (global + local) — double-tap ?',
      },
    },
  },
}
