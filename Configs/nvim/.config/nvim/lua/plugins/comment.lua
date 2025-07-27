return {
  -- "gc" to comment visual regions/lines
  { 
    'numToStr/Comment.nvim', 
    config = function()
      require('Comment').setup({
        mappings = false,  -- Disable all default mappings
      })
      
      -- Only create the operators we want
      vim.keymap.set('n', 'gc', '<Plug>(comment_toggle_linewise)', { desc = 'Comment toggle linewise' })
      vim.keymap.set('x', 'gc', '<Plug>(comment_toggle_linewise_visual)', { desc = 'Comment toggle linewise (visual)' })
      vim.keymap.set('n', 'gb', '<Plug>(comment_toggle_blockwise)', { desc = 'Comment toggle blockwise' })
      vim.keymap.set('x', 'gb', '<Plug>(comment_toggle_blockwise_visual)', { desc = 'Comment toggle blockwise (visual)' })
      
      -- Explicitly unmap any conflicting keymaps that might still exist
      pcall(vim.keymap.del, 'n', 'gcc')
      pcall(vim.keymap.del, 'n', 'gbc')
    end
  },
}