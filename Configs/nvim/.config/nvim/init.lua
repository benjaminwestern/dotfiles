-- https://learnxinyminutes.com/docs/lua/
-- https://neovim.io/doc/user/lua-guide.html

-- Disable netrw
-- vim.g.loaded_netrw          = 1
-- vim.g.loaded_netrwPlugin    = 1

-- See `:help mapleader`
vim.g.mapleader             = ' '
vim.g.maplocalleader        = ' '
vim.g.copilot_assume_mapped = true

-- Set to true if you have a Nerd Font installed and selected in the terminal
vim.g.have_nerd_font        = true

-- Vim Line numbers
vim.opt.number              = true
vim.opt.relativenumber      = true
vim.opt.signcolumn          = "number"

-- [[ Setting options ]]
-- See `:help vim.o`

-- Set highlight on search
vim.o.hlsearch              = false

-- Make line numbers default
vim.wo.number               = true

-- Enable mouse mode
vim.o.mouse                 = 'a'

-- Sync clipboard between OS and Neovim.
-- See `:help 'clipboard'`
vim.o.clipboard             = 'unnamedplus'

-- Enable break indent
vim.o.breakindent           = true

-- Save undo history
vim.o.undofile              = true

-- Case-insensitive searching UNLESS \C or capital in search
vim.o.ignorecase            = true
vim.o.smartcase             = true

-- Keep signcolumn on by default
vim.wo.signcolumn           = 'yes'

-- Decrease update time
vim.o.updatetime            = 250
vim.o.timeoutlen            = 300

-- Set completeopt to have a better completion experience
vim.o.completeopt           = 'menuone,noselect'

-- Set better colors for the command line
vim.o.termguicolors         = true

-- [[ Configure LSP Diagnostics ]]
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
if not vim.loop.fs_stat(lazypath) then
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

-- Add mise predicate for Treesitter TOML injection queries
vim.treesitter.query.add_predicate("is-mise?", function(match, pattern, bufnr, predicate, metadata)
  local filename = vim.api.nvim_buf_get_name(bufnr)
  return filename:match("mise") ~= nil
end, { force = true })

require('lazy').setup({
  { import = 'plugins' },
}, {})

-- [[ Basic Keymaps ]]

-- Keymaps for better default experience
-- See `:help vim.keymap.set()`
vim.keymap.set({ 'n', 'v' }, '<Space>', '<Nop>', { silent = true })

-- Remap for dealing with word wrap
vim.keymap.set('n', 'k', "v:count == 0 ? 'gk' : 'k'", { expr = true, silent = true })
vim.keymap.set('n', 'j', "v:count == 0 ? 'gj' : 'j'", { expr = true, silent = true })

-- Diagnostic keymaps
vim.keymap.set('n', '[d', vim.diagnostic.goto_prev, { desc = 'Go to previous diagnostic message' })
vim.keymap.set('n', ']d', vim.diagnostic.goto_next, { desc = 'Go to next diagnostic message' })
vim.keymap.set('n', '<leader>e', vim.diagnostic.open_float, { desc = 'Open floating diagnostic message' })
vim.keymap.set('n', '<leader>q', vim.diagnostic.setloclist, { desc = 'Open diagnostics list' })

-- Replace :Ex with Yazi
-- vim.api.nvim_create_user_command('Ex', function()
--   vim.cmd('Yazi')
-- end, { desc = 'Open Yazi file manager' })

-- [[ Highlight on yank ]]
-- See `:help vim.highlight.on_yank()`
local highlight_group = vim.api.nvim_create_augroup('YankHighlight', { clear = true })
vim.api.nvim_create_autocmd('TextYankPost', {
  callback = function()
    vim.highlight.on_yank()
  end,
  group = highlight_group,
  pattern = '*',
})
