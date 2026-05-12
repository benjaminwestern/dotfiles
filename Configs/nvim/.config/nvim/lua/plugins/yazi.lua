return {
  "mikavilpas/yazi.nvim",
  event = "VeryLazy",
  keys = {
    -- Open yazi at the current file's directory (primary file browser)
    {
      "<leader>n",
      function()
        require("yazi").yazi(nil, vim.fn.expand("%:p"))
      end,
      desc = "Open yazi at the current file",
    },
    -- Open yazi at the current working directory
    {
      "<leader>N",
      "<cmd>Yazi cwd<cr>",
      desc = "Open yazi at cwd",
    },
    -- Toggle the last yazi session
    {
      "<c-up>",
      "<cmd>Yazi toggle<cr>",
      desc = "Resume the last yazi session",
    },
  },
  opts = {
    -- Don't auto-open when nvim starts with a directory argument
    -- Use <leader>n or <leader>N to open yazi manually
    open_for_directories = false,
    -- Make the floating window take up more screen for better browsing
    floating_window_scaling_factor = 0.85,
    -- Slightly transparent to see the editor behind
    yazi_floating_window_winblend = 0,
    -- Use a nice rounded border
    yazi_floating_window_border = "rounded",
    -- When yazi closes without a file selection, change nvim's cwd to yazi's last directory
    change_neovim_cwd_on_close = true,
    -- Highlight buffers that are in the same directory as the hovered file
    highlight_hovered_buffers_in_same_directory = true,
    keymaps = {
      show_help = "<f1>",
      open_file_in_vertical_split = "<c-v>",
      open_file_in_horizontal_split = "<c-x>",
      open_file_in_tab = "<c-t>",
      grep_in_directory = "<c-s>",
      replace_in_directory = "<c-g>",
      cycle_open_buffers = "<tab>",
      copy_relative_path_to_selected_files = "<c-y>",
      send_to_quickfix_list = "<c-q>",
      change_working_directory = "<c-\\>",
      open_and_pick_window = "<c-o>",
    },
    integrations = {
      -- Use telescope for grepping in yazi directories
      grep_in_directory = function(directory)
        require("telescope.builtin").live_grep({
          prompt_title = "Grep in " .. directory,
          cwd = directory,
        })
      end,
      grep_in_selected_files = function(selected_files)
        require("telescope.builtin").live_grep({
          prompt_title = "Grep in selected files",
          search_dirs = selected_files,
        })
      end,
    },
  },
}
