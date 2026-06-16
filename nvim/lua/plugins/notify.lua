-- =============================================================================
-- ||                                                                         ||
-- ||                         NVIM / PLUGIN / NOTIFY                          ||
-- ||                                                                         ||
-- =============================================================================
return {
  'rcarriga/nvim-notify',
  lazy = false,
  priority = 500,
  config = function()
    local notify = require 'notify'
    notify.setup {
      stages = 'fade_in_slide_out',
      timeout = 3000,
      max_width = function()
        return math.floor(vim.o.columns * 0.4)
      end,
      max_height = function()
        return math.floor(vim.o.lines * 0.3)
      end,
      background_colour = 'Normal',
      icons = {
        ERROR = '',
        WARN = '',
        INFO = '',
        DEBUG = '',
        TRACE = '✎',
      },
    }
    -- Set as default notification handler
    vim.notify = notify
  end,
  keys = {
    {
      '<leader>un',
      function()
        require('notify').history { max_width = 80, max_height = 20 }
      end,
      desc = '[U]nread [N]otifications history',
    },
    {
      '<leader>uN',
      function()
        require('notify').dismiss { silent = true, pending = true }
      end,
      desc = '[U]nread [N]otifications dismiss all',
    },
  },
}
