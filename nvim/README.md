# Neovim config

A compact Neovim setup focused on fast navigation, lightweight UI, LSP-backed editing, and a small set of familiar defaults. It keeps native Vim flows like `:Ex`, adds Telescope where fuzzy search helps, and avoids bulky sidebars or full-screen plugin UIs unless they pay their way.

## Quick start

Open Neovim from any project:

```bash
nvim
```

Useful first checks:

```vim
:Lazy
:checkhealth
:Ex
```

The most common navigation keys are:

| Key | Action |
| --- | --- |
| `Ctrl-f` | Find files with Telescope |
| `Ctrl-g` | Live grep with Telescope |
| `Space Space` | Switch open buffers in MRU order |
| `:` | Normal bottom command line with native completion |
| `:Ex` | Native netrw file explorer |
| `Space sk` | Search all keymaps |
| `Space ??` | Show all which-key mappings |

## Design goals

- Keep the editor light and legible. The bottom bar shows only mode, repo/branch, path, diagnostics when present, filetype, and cursor location.
- Prefer native Neovim behaviour where it is already good. `:Ex` uses stock netrw without config-level wrappers or helper mappings.
- Use Telescope for fuzzy workflows. File search, grep, buffers, diagnostics, keymaps, commands, LSP symbols, and git pickers all route through Telescope.
- Avoid duplicate file managers and git TUIs. Yazi and Lazygit are intentionally not part of this config.

## File layout

```text
init.lua                  Core options, diagnostics, lazy.nvim bootstrap
lua/keymaps.lua           Global mappings, Telescope shortcuts, macOS open helpers
lua/health.lua            Local health checks
lua/plugins/*.lua         Lazy plugin specs grouped by concern
after/queries/            Treesitter query customisation
lazy-lock.json            Lazy lockfile when tracked/managed locally
.stylua.toml              Lua formatting rules
```

## Plugin groups

| File | Purpose |
| --- | --- |
| `completion.lua` | Completion via `blink.cmp` and snippets via `friendly-snippets` |
| `debug.lua` | Debug Adapter Protocol setup with `nvim-dap`, DAP UI, Mason integration, and Go support |
| `dracula.lua` | Dracula colour scheme |
| `formatting.lua` | Formatting through `conform.nvim` |
| `gitsigns.lua` | Inline git hunks, blame, previews, and diff actions |
| `indent-blankline.lua` | Indentation guides |
| `lint.lua` | Linting through `nvim-lint` |
| `lsp.lua` | LSP setup through `nvim-lspconfig`, Mason, fidget, and lazydev |
| `markdown.lua` | Markdown preview in the browser |
| `mini.lua` | Mini modules for statusline, text objects, movement, pairs, operators, whitespace, and buffer deletion |
| `misc.lua` | Small utility plugins: `vim-sleuth`, web devicons, and smartcolumn |
| `notify.lua` | Notification UI via `nvim-notify` |
| `otter.lua` | Embedded-language LSP support for Markdown and mise TOML files |
| `telescope.lua` | Telescope setup and search/navigation mappings |
| `todo-comments.lua` | TODO/FIXME/HACK/NOTE search and highlighting |
| `treesitter.lua` | Treesitter parser install and highlighting/indent integration |
| `trouble.lua` | Diagnostics, references, and quickfix panels |
| `which-key.lua` | Discoverable keymap descriptions |

## Daily workflow

### Find and move

| Key | Action |
| --- | --- |
| `Ctrl-f` | Find files in the current project |
| `Ctrl-g` | Search text across the current project |
| `Space /` | Fuzzy search inside the current buffer |
| `Space Space` | Switch buffers by most recently used order |
| `Space sf` | Find files |
| `Space sg` | Live grep |
| `Space s.` | Recent files |
| `Space sk` | Search keymaps |
| `Space sc` | Search commands |

### Explore files

`:Ex` opens stock netrw. This config does not add netrw-specific mappings, sort commands, Telescope hooks, or statusline wrappers.

### Code intelligence

| Key | Action |
| --- | --- |
| `gd` | Go to definition |
| `gr` | Find references |
| `gI` | Go to implementation |
| `gD` | Go to declaration |
| `grn` | Rename symbol |
| `K` | Hover documentation |
| `Space k` | Signature help |
| `Space ca` | Code action |
| `Space D` | Type definition |
| `Space ds` | Document symbols |
| `Space ws` | Workspace symbols |
| `Space f` | Format buffer |

### Diagnostics and git

| Key | Action |
| --- | --- |
| `[d` / `]d` | Previous / next diagnostic |
| `Space df` | Diagnostic float under cursor |
| `Space q` | Trouble diagnostics panel |
| `Space Q` | Trouble diagnostics for current buffer |
| `[c` / `]c` | Previous / next git hunk |
| `Space gs` | Git status picker |
| `Space gh` | Git hunks picker |
| `Space hs` | Stage hunk |
| `Space hr` | Reset hunk |
| `Space hp` | Preview hunk |
| `Space hb` | Blame line |

## UI model

The UI stays deliberately sparse.

- The statusline comes from `mini.statusline` and is customised in `mini.lua`. It shows mode, repo/branch, current path, diagnostics only when present, filetype, and `line:column`.
- The command line uses Neovim's normal bottom command line with native completion. There is no centred command popup.
- Telescope uses dropdowns for quick pickers, an ivy layout for live grep, and previews only where context is useful.
- Which-key documents mappings, but it does not replace learning the core keys. Use `Space ??` or `Space sk` when you forget something.

## Intentional non-goals

- No Yazi integration. Native `:Ex` plus Telescope covers the current file browsing workflow.
- No Lazygit integration. Git workflows use Telescope and Gitsigns inside Neovim.
- No file-tree sidebar. The config favours fuzzy search, buffers, and netrw over a persistent tree.
- No command-line popup UI. Command completion stays native and lightweight.

## Maintenance

Use Lazy to inspect and update plugins:

```vim
:Lazy
:Lazy sync
:Lazy clean
```

Format Lua after larger edits:

```bash
stylua nvim
```

Useful verification commands from the repo root:

```bash
nvim --headless '+checkhealth' +qa
nvim --headless '+lua require("mini.statusline").active()' +qa
nvim --headless '+lua assert(vim.o.cmdheight == 1)' '+lua assert(vim.o.wildoptions == "")' '+lua assert(require("blink.cmp.config").cmdline.enabled == false)' '+lua assert(not require("lazy.core.config").plugins["wilder.nvim"])' +qa
```

## Related docs

- `KEYBINDS.md` in the repo root is the printable keybinding cheat sheet.
- `README.md` explains the repository bootstrap and managed config model.
