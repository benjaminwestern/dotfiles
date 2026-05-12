return {
  {
    -- [[ Open file in external application / Finder ]]
    -- Neovim 0.10+ provides vim.ui.open() which uses the OS default handler.
    -- On macOS this calls `open`, so images, PDFs, markdown previews, etc. just work.
    'mikavilpas/yazi.nvim', -- keep as dependency so this loads after yazi
    keys = {
      {
        '<leader>oo',
        function()
          local filepath = vim.api.nvim_buf_get_name(0)
          if filepath == '' then
            print 'No file in current buffer'
            return
          end
          vim.ui.open(filepath)
        end,
        desc = '[O]pen file in default [O]S application',
      },
      {
        '<leader>of',
        function()
          local filepath = vim.api.nvim_buf_get_name(0)
          if filepath == '' then
            print 'No file in current buffer'
            return
          end
          vim.fn.jobstart({ 'open', '-R', filepath }, { detach = true })
        end,
        desc = '[O]pen in [F]inder (reveal file)',
      },
      {
        '<leader>oF',
        function()
          local filepath = vim.api.nvim_buf_get_name(0)
          local dir = filepath == '' and vim.fn.getcwd() or vim.fn.fnamemodify(filepath, ':h')
          vim.fn.jobstart({ 'open', dir }, { detach = true })
        end,
        desc = "[O]pen file's directory in [F]inder",
      },
    },
  },
}
