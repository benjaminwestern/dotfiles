return {
  "NachoNievaG/atac.nvim",
  dependencies = { "akinsho/toggleterm.nvim" },
  config = function()
    require("atac").setup({
      dir = "~/.config/nvim/atac", -- By default, the dir will be set as /tmp/atac
    })
  end,
  vim.keymap.set('n', '<leader>r', ':Atac<cr>', { desc = 'Open ATAC Client' })
}
