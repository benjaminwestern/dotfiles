-- =============================================================================
-- ||                                                                         ||
-- ||                          NVIM / PLUGIN / DEBUG                          ||
-- ||                                                                         ||
-- =============================================================================
return {
  {
    'mfussenegger/nvim-dap',
    dependencies = {
      -- Beautiful debugger UI
      'rcarriga/nvim-dap-ui',
      -- Required dependency for nvim-dap-ui
      'nvim-neotest/nvim-nio',
      -- Installs debug adapters via Mason
      'mason-org/mason.nvim',
      'jay-babu/mason-nvim-dap.nvim',
      -- Go debugger helper
      'leoluz/nvim-dap-go',
    },
    keys = {
      -- Debug session control
      {
        '<leader>dc',
        function()
          require('dap').continue()
        end,
        desc = '[D]ebug [C]ontinue / Start',
      },
      {
        '<leader>dt',
        function()
          require('dap').terminate()
        end,
        desc = '[D]ebug [T]erminate',
      },
      -- Stepping
      {
        '<leader>di',
        function()
          require('dap').step_into()
        end,
        desc = '[D]ebug step [I]nto',
      },
      {
        '<leader>do',
        function()
          require('dap').step_over()
        end,
        desc = '[D]ebug step [O]ver',
      },
      {
        '<leader>dO',
        function()
          require('dap').step_out()
        end,
        desc = '[D]ebug step [O]ut',
      },
      -- Breakpoints
      {
        '<leader>db',
        function()
          require('dap').toggle_breakpoint()
        end,
        desc = '[D]ebug toggle [B]reakpoint',
      },
      {
        '<leader>dB',
        function()
          require('dap').set_breakpoint(vim.fn.input 'Breakpoint condition: ')
        end,
        desc = '[D]ebug set conditional [B]reakpoint',
      },
      {
        '<leader>dl',
        function()
          require('dap').set_breakpoint(nil, nil, vim.fn.input 'Log point message: ')
        end,
        desc = '[D]ebug set [L]og point',
      },
      -- UI toggle
      {
        '<leader>du',
        function()
          require('dapui').toggle()
        end,
        desc = '[D]ebug toggle [U]I',
      },
      -- Repl
      {
        '<leader>dr',
        function()
          require('dap').repl.toggle()
        end,
        desc = '[D]ebug toggle [R]EPL',
      },
      -- Run last
      {
        '<leader>dL',
        function()
          require('dap').run_last()
        end,
        desc = '[D]ebug run [L]ast',
      },
    },
    config = function()
      local dap = require 'dap'
      local dapui = require 'dapui'

      -- Mason-nvim-dap: install adapters automatically.
      require('mason-nvim-dap').setup {
        automatic_installation = true,
        ensure_installed = {
          'delve',         -- Go
          'debugpy',       -- Python
          'js-debug-adapter', -- JavaScript/TypeScript (modern)
          'codelldb',      -- Rust / C / C++
        },
      }

      -- Dap UI setup
      dapui.setup {
        icons = { expanded = '▾', collapsed = '▸', current_frame = '*' },
        controls = {
          icons = {
            pause = '⏸',
            play = '▶',
            step_into = '⏎',
            step_over = '⏭',
            step_out = '⏮',
            step_back = 'b',
            run_last = '▶▶',
            terminate = '⏹',
            disconnect = '⏏',
          },
        },
        layouts = {
          {
            elements = {
              { id = 'scopes', size = 0.25 },
              { id = 'breakpoints', size = 0.25 },
              { id = 'stacks', size = 0.25 },
              { id = 'watches', size = 0.25 },
            },
            size = 40,
            position = 'left',
          },
          {
            elements = {
              { id = 'repl', size = 0.5 },
              { id = 'console', size = 0.5 },
            },
            size = 10,
            position = 'bottom',
          },
        },
      }

      -- Auto-open/close DAP UI
      dap.listeners.after.event_initialized['dapui_config'] = function()
        dapui.open()
      end
      dap.listeners.before.event_terminated['dapui_config'] = function()
        dapui.close()
      end
      dap.listeners.before.event_exited['dapui_config'] = function()
        dapui.close()
      end

      -- -----------------------------------------------------------------------------
      -- GO
      -- -----------------------------------------------------------------------------
      require('dap-go').setup {
        delve = {
          detached = vim.fn.has 'win32' == 0,
        },
      }

      -- -----------------------------------------------------------------------------
      -- JAVASCRIPT / TYPESCRIPT (modern js-debug-adapter)
      -- -----------------------------------------------------------------------------
      -- The modern adapter is installed by Mason as `js-debug-adapter`.
      -- It provides a single `pwa-node` adapter type.
      dap.adapters['pwa-node'] = {
        type = 'server',
        host = 'localhost',
        port = '${port}',
        executable = {
          command = 'node',
          args = {
            vim.fn.stdpath 'data' .. '/mason/packages/js-debug-adapter/js-debug/src/dapDebugServer.js',
            '${port}',
          },
        },
      }

      local js_ts_configs = {
        {
          type = 'pwa-node',
          request = 'launch',
          name = 'Launch file',
          program = '${file}',
          cwd = '${workspaceFolder}',
          sourceMaps = true,
          skipFiles = { '<node_internals>/**' },
        },
        {
          type = 'pwa-node',
          request = 'attach',
          name = 'Attach',
          processId = require('dap.utils').pick_process,
          cwd = '${workspaceFolder}',
          sourceMaps = true,
          skipFiles = { '<node_internals>/**' },
        },
      }

      dap.configurations.javascript = js_ts_configs
      dap.configurations.typescript = js_ts_configs
      dap.configurations.javascriptreact = js_ts_configs
      dap.configurations.typescriptreact = js_ts_configs

      -- -----------------------------------------------------------------------------
      -- PYTHON (debugpy)
      -- -----------------------------------------------------------------------------
      dap.adapters.python = {
        type = 'executable',
        command = vim.fn.stdpath 'data' .. '/mason/packages/debugpy/venv/bin/python',
        args = { '-m', 'debugpy.adapter' },
      }

      dap.configurations.python = {
        {
          type = 'python',
          request = 'launch',
          name = 'Launch file',
          program = '${file}',
          pythonPath = function()
            -- Try to detect the active Python interpreter
            local venv = os.getenv 'VIRTUAL_ENV'
            if venv then
              return venv .. '/bin/python'
            end
            -- Try `python3` or `python` from PATH
            for _, cmd in ipairs { 'python3', 'python' } do
              if vim.fn.executable(cmd) == 1 then
                return vim.fn.exepath(cmd)
              end
            end
            return 'python3'
          end,
          console = 'integratedTerminal',
        },
        {
          type = 'python',
          request = 'launch',
          name = 'Launch file with arguments',
          program = '${file}',
          args = function()
            local args_string = vim.fn.input 'Arguments: '
            return vim.split(args_string, ' +')
          end,
          pythonPath = function()
            local venv = os.getenv 'VIRTUAL_ENV'
            if venv then
              return venv .. '/bin/python'
            end
            for _, cmd in ipairs { 'python3', 'python' } do
              if vim.fn.executable(cmd) == 1 then
                return vim.fn.exepath(cmd)
              end
            end
            return 'python3'
          end,
          console = 'integratedTerminal',
        },
        {
          type = 'python',
          request = 'attach',
          name = 'Attach to process',
          processId = require('dap.utils').pick_process,
        },
      }

      -- -----------------------------------------------------------------------------
      -- RUST (codelldb)
      -- -----------------------------------------------------------------------------
      dap.adapters.codelldb = {
        type = 'server',
        port = '${port}',
        executable = {
          command = vim.fn.stdpath 'data' .. '/mason/packages/codelldb/codelldb',
          args = { '--port', '${port}' },
          detached = vim.fn.has 'win32' == 0,
        },
      }

      dap.configurations.rust = {
        {
          name = 'Debug (codelldb)',
          type = 'codelldb',
          request = 'launch',
          program = function()
            -- Prompt for the binary path, or try to guess from Cargo
            local default = vim.fn.getcwd() .. '/target/debug/' .. vim.fn.fnamemodify(vim.fn.getcwd(), ':t')
            return vim.fn.input('Path to executable: ', default, 'file')
          end,
          cwd = '${workspaceFolder}',
          stopOnEntry = false,
          sourceLanguages = { 'rust' },
        },
      }

      -- -----------------------------------------------------------------------------
      -- ZIG (codelldb works for Zig too)
      -- -----------------------------------------------------------------------------
      dap.configurations.zig = {
        {
          name = 'Debug (codelldb)',
          type = 'codelldb',
          request = 'launch',
          program = function()
            local default = vim.fn.getcwd() .. '/zig-out/bin/' .. vim.fn.fnamemodify(vim.fn.getcwd(), ':t')
            return vim.fn.input('Path to executable: ', default, 'file')
          end,
          cwd = '${workspaceFolder}',
          stopOnEntry = false,
        },
      }
    end,
  },
}
