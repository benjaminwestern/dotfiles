return {
  "mikavilpas/yazi.nvim",
  event = "VimEnter",
  keys = {
    -- 👇 in this section, choose your own keymappings!
    {
      "<leader>n",
      "<cmd>Yazi<cr>",
      desc = "Open yazi at the current file",
    },
    {
      -- Open in the current working directory
      "<leader>cw",
      "<cmd>Yazi cwd<cr>",
      desc = "Open the file manager in nvim's working directory",
    },
    {
      -- NOTE: this requires a version of yazi that includes
      -- https://github.com/sxyazi/yazi/pull/1305 from 2024-07-18
      "<c-up>",
      "<cmd>Yazi toggle<cr>",
      desc = "Resume the last yazi session",
    },
  },
  opts = {
    -- Replace netrw with yazi
    open_for_directories = true,
    keymaps = {
      show_help = "<f1>",
      copy_relative_path_to_selected_files = nil,
    },
    yazi_floating_window_border = "none"
  },
}