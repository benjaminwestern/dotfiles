-- =============================================================================
-- ||                                                                         ||
-- ||                         NVIM / PLUGIN / WILDER                          ||
-- ||                                                                         ||
-- =============================================================================
return {
  'gelguy/wilder.nvim',
  event = 'CmdlineEnter',
  config = function()
    local wilder = require('wilder')

    wilder.setup({
      modes = { ':' },
      next_key = '<Tab>',
      previous_key = '<S-Tab>',
      accept_key = '<Down>',
      reject_key = '<Up>',
    })

    -- Keep this light: use Vim's built-in command-line completion engine,
    -- not Python remote plugins or a heavier command UI.
    wilder.set_option('use_python_remote_plugin', 0)
    wilder.set_option('pipeline', {
      wilder.branch(
        wilder.cmdline_pipeline({
          language = 'vim',
          fuzzy = 1,
        }),
        wilder.history()
      ),
    })

    wilder.set_option('renderer', wilder.popupmenu_renderer(
      wilder.popupmenu_palette_theme({
        border = 'rounded',
        max_height = '35%',
        min_height = 0,
        prompt_position = 'top',
        reverse = 0,
        highlighter = wilder.basic_highlighter(),
      })
    ))
  end,
}
