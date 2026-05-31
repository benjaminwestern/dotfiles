-- =============================================================================
-- ||                                                                         ||
-- ||                       NVIM / PLUGIN / COMPLETION                        ||
-- ||                                                                         ||
-- =============================================================================
return {
  {
    -- Modern autocompletion
    'saghen/blink.cmp',
    lazy = false,
    dependencies = 'rafamadriz/friendly-snippets',
    version = 'v1.*',
    opts = {
      keymap = { preset = 'default' },
      appearance = {
        use_nvim_cmp_as_default = true,
        nerd_font_variant = 'mono',
      },
      sources = {
        default = { 'lsp', 'path', 'snippets', 'buffer' },
      },
      -- Keep `:` on Neovim's native command line instead of blink's popup menu.
      cmdline = { enabled = false },
      signature = { enabled = true },
    },
    opts_extend = { 'sources.default' },
  },
}
