-- =============================================================================
-- ||                                                                         ||
-- ||                               NVIM / INIT                               ||
-- ||                                                                         ||
-- =============================================================================
-- https://learnxinyminutes.com/docs/lua/
-- https://neovim.io/doc/user/lua-guide.html

-- See `:help mapleader`
vim.g.mapleader             = ' '
vim.g.maplocalleader        = ' '

-- Set to true if you have a Nerd Font installed and selected in the terminal
vim.g.have_nerd_font        = true

-- Vim Line numbers
vim.o.number                = true
vim.o.relativenumber        = true
vim.o.signcolumn            = 'number'

-- Indentation: 4 spaces, insert spaces for tabs
vim.o.tabstop               = 4
vim.o.shiftwidth            = 4
vim.o.softtabstop           = 4
vim.o.expandtab             = true
vim.o.smartindent           = true

-- -----------------------------------------------------------------------------
-- SETTING OPTIONS
-- -----------------------------------------------------------------------------
-- See `:help vim.o`

-- Highlight current line for easy tracking
vim.o.cursorline            = true

-- Keep 8 lines visible above/below cursor (don't hug screen edge)
vim.o.scrolloff             = 8
vim.o.sidescrolloff         = 8

-- Highlight search matches, press <Esc> to clear highlights when done
vim.o.hlsearch              = true

-- Enable mouse mode
vim.o.mouse                 = 'a'

-- Don't show mode in command line (already in statusline)
vim.o.showmode              = false
vim.o.showcmd               = false
vim.o.ruler                 = false
vim.o.laststatus            = 3
vim.o.cmdheight             = 0

-- NOTE: clipboard is NOT synced by default. We explicitly map yank keys
-- to the + register so only intentional yanks go to the system clipboard.
-- Deletes (d/x/c) stay internal-only and are recoverable with p.

-- Enable break indent
vim.o.breakindent           = true

-- Save undo history
vim.o.undofile              = true

-- Case-insensitive searching UNLESS \C or capital in search
vim.o.ignorecase            = true
vim.o.smartcase             = true

-- Decrease update time
vim.o.updatetime            = 250
vim.o.timeoutlen            = 300

-- Set completeopt to have a better completion experience
vim.o.completeopt           = 'menuone,noselect'

-- Command-line completion with a light popup menu.
vim.o.wildmenu              = true
vim.o.wildmode              = 'longest:full,full'
vim.o.wildoptions           = 'pum'
vim.o.wildignorecase        = true
vim.o.pumheight             = 12
vim.o.pumblend              = 0

-- Configure how new splits should open
vim.o.splitright            = true
vim.o.splitbelow            = true

-- Show whitespace characters: tabs as » and trailing spaces as ·
vim.o.list                  = true
vim.opt.listchars           = { tab = '» ', trail = '·', nbsp = '␣' }

-- Live preview substitutions as you type (:s/foo/bar shows split)
vim.o.inccommand            = 'split'

-- Confirm dialog instead of error when quitting unsaved buffer
vim.o.confirm               = true

-- Set better colors for the command line
vim.o.termguicolors         = true

-- -----------------------------------------------------------------------------
-- FOLDS — COLLAPSE/EXPAND CODE BLOCKS
-- -----------------------------------------------------------------------------
-- Treesitter-powered folds. zc to close, zo to open, za to toggle.
vim.o.foldmethod            = 'expr'
vim.o.foldexpr              = 'v:lua.vim.treesitter.foldexpr()'
vim.o.foldenable            = true
vim.o.foldlevel             = 99
vim.o.foldlevelstart        = 99

-- -----------------------------------------------------------------------------
-- CONFIGURE LSP DIAGNOSTICS
-- -----------------------------------------------------------------------------
vim.diagnostic.config {
  virtual_text = {
    spacing = 4,
    source = 'if_many',
    prefix = '●',
  },
  float = {
    focusable = false,
    style = 'minimal',
    border = 'rounded',
    source = 'always',
    header = '',
    prefix = '',
  },
  signs = true,
  underline = true,
  update_in_insert = false,
  severity_sort = true,
}

-- `:help lazy.nvim.txt` for more info
local lazypath = vim.fn.stdpath 'data' .. '/lazy/lazy.nvim'
if not vim.uv.fs_stat(lazypath) then
  vim.fn.system {
    'git',
    'clone',
    '--filter=blob:none',
    'https://github.com/folke/lazy.nvim.git',
    '--branch=stable', -- latest stable release
    lazypath,
  }
end
vim.opt.rtp:prepend(lazypath)

-- Prepend mise shims to PATH
vim.env.PATH = vim.env.HOME .. "/.local/share/mise/shims:" .. vim.env.PATH

-- Unset GOBIN so Mason's `go install` builds place binaries in the temp
-- GOPATH/bin where Mason expects them, instead of the mise Go directory.
-- Mise shims remain on PATH, so running Go binaries is unaffected.
vim.env.GOBIN = nil

-- Add mise predicate for Treesitter TOML injection queries
vim.treesitter.query.add_predicate("is-mise?", function(match, pattern, bufnr, predicate, metadata)
  local filename = vim.api.nvim_buf_get_name(bufnr)
  return filename:match("mise") ~= nil
end, { force = true })

-- Load global keymaps (not plugin-specific)
require('keymaps')

require('lazy').setup({
  { import = 'plugins' },
}, {})
