return {
  {
    -- Highlight, edit, and navigate code
    'nvim-treesitter/nvim-treesitter',
    -- NOTE: The `main` branch is a full rewrite for Neovim 0.12+.
    -- The `master` branch is locked for backward compatibility.
    -- Kickstart and modern configs use `main`.
    branch = 'main',
    lazy = false,
    build = ':TSUpdate',
    config = function()
      -- Ensure basic parsers are installed.
      -- Add any languages you use regularly to this list.
      local parsers = {
        'bash', 'c', 'cpp', 'go', 'lua', 'luadoc', 'markdown', 'markdown_inline',
        'python', 'rust', 'terraform', 'tsx', 'javascript', 'typescript',
        'vim', 'vimdoc', 'json', 'http', 'xml', 'graphql', 'query', 'diff', 'html',
      }
      require('nvim-treesitter').install(parsers)

      ---Try to attach treesitter to a buffer for a given language.
      ---@param buf integer
      ---@param language string
      local function treesitter_try_attach(buf, language)
        -- Check if a parser exists and load it
        if not vim.treesitter.language.add(language) then
          return
        end
        -- Enable syntax highlighting and other treesitter features
        vim.treesitter.start(buf, language)

        -- Enable treesitter based indentation if available
        local has_indent_query = vim.treesitter.query.get(language, 'indents') ~= nil
        if has_indent_query then
          vim.bo[buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
        end
      end

      local available_parsers = require('nvim-treesitter').get_available()
      vim.api.nvim_create_autocmd('FileType', {
        callback = function(args)
          local buf, filetype = args.buf, args.match

          local language = vim.treesitter.language.get_lang(filetype)
          if not language then
            return
          end

          local installed_parsers = require('nvim-treesitter').get_installed 'parsers'

          if vim.tbl_contains(installed_parsers, language) then
            -- Enable the parser if it is already installed
            treesitter_try_attach(buf, language)
          elseif vim.tbl_contains(available_parsers, language) then
            -- If a parser is available in nvim-treesitter, auto-install it and enable it after installation
            require('nvim-treesitter').install(language):await(function()
              treesitter_try_attach(buf, language)
            end)
          else
            -- Try to enable treesitter features in case the parser exists but is not available from nvim-treesitter
            treesitter_try_attach(buf, language)
          end
        end,
      })
    end,
  },
}
