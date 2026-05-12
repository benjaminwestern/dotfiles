-- [[ Global Keymaps ]]
-- These are not plugin-specific and live at the top level.

-- Disable default <Space> behavior
vim.keymap.set({ 'n', 'v' }, '<Space>', '<Nop>', { silent = true })

-- <Esc> clears search highlights (after searching with / or ?)
vim.keymap.set('n', '<Esc>', '<cmd>nohlsearch<cr>', { desc = 'Clear search highlights' })

-- Remap for dealing with word wrap
vim.keymap.set('n', 'k', "v:count == 0 ? 'gk' : 'k'", { expr = true, silent = true })
vim.keymap.set('n', 'j', "v:count == 0 ? 'gj' : 'j'", { expr = true, silent = true })

-- [[ Clipboard: yank goes to system, delete stays internal ]]
-- d/x/c use default registers (recoverable with p, not on system clipboard)
-- y/yy/Y explicitly target the + register (system clipboard)
vim.keymap.set({ 'n', 'v' }, 'y', '"+y', { noremap = true, desc = 'Yank to clipboard' })
vim.keymap.set('n', 'yy', '"+yy', { noremap = true, desc = 'Yank line to clipboard' })
vim.keymap.set({ 'n', 'v' }, 'Y', '"+Y', { noremap = true, desc = 'Yank to end of line to clipboard' })
-- Paste from system clipboard explicitly with <leader>p
vim.keymap.set({ 'n', 'v' }, '<leader>p', '"+p', { noremap = true, desc = 'Paste from system clipboard' })
vim.keymap.set({ 'n', 'v' }, '<leader>P', '"+P', { noremap = true, desc = 'Paste before from system clipboard' })

-- [[ Highlight on yank ]]
-- See `:help vim.hl.on_yank()`
local highlight_group = vim.api.nvim_create_augroup('YankHighlight', { clear = true })
vim.api.nvim_create_autocmd('TextYankPost', {
  callback = function()
    vim.hl.on_yank()
  end,
  group = highlight_group,
  pattern = '*',
})
