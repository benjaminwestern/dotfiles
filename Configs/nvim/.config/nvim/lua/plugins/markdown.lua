-- =============================================================================
-- ||                                                                         ||
-- ||                        NVIM / PLUGIN / MARKDOWN                         ||
-- ||                                                                         ||
-- =============================================================================
return {
  {
    -- Markdown preview in the browser. Live-reloads as you edit.
    -- This is the primary replacement for VSCode's built-in markdown preview.
    'iamcco/markdown-preview.nvim',
    cmd = { 'MarkdownPreviewToggle', 'MarkdownPreview', 'MarkdownPreviewStop' },
    build = 'cd app && npm install && git checkout .',
    ft = { 'markdown' },
    config = function()
      -- Do not auto-start preview when opening a markdown file
      vim.g.mkdp_auto_start = 0
      -- Auto-close preview when switching away from markdown
      vim.g.mkdp_auto_close = 1
      -- Refresh on save or leave insert mode
      vim.g.mkdp_refresh_slow = 0
      -- Use dark theme by default
      vim.g.mkdp_theme = 'dark'
      -- Use a custom port (avoid conflicts)
      vim.g.mkdp_port = '8830'
      -- Open preview in the default browser
      vim.g.mkdp_browser = ''

      -- Keymaps for markdown preview
      vim.keymap.set('n', '<leader>om', '<cmd>MarkdownPreviewToggle<cr>', { desc = '[O]pen [M]arkdown preview in browser' })
    end,
  },
}
