local lazy = require("flutter-tools.lazy")
local path = lazy.require("flutter-tools.utils.path") ---@module "flutter-tools.utils.path"

local ui = require("flutter-tools.ui")

local success, dap = pcall(require, "dap")
if not success then
  ui.notify(string.format("nvim-dap is not installed!\n%s", dap), ui.ERROR)
  return
end

local M = {}

function M.setup(config)
  local opts = config.debugger
  require("flutter-tools.executable").get(function(paths)
    local root_patterns = { ".git", "pubspec.yaml" }
    local current_dir = vim.fn.expand("%:p:h")
    local root_dir = path.find_root(root_patterns, current_dir) or current_dir
    local function search_pubspec_for_flutter_sdk()
      local pubspec_path = path.join(root_dir, "pubspec.yaml")
      return pcall(vim.cmd, "silent 1vimgrep! /sdk:\\_s\\+flutter\\C/j" .. pubspec_path)
    end
    local is_flutter_project = vim.loop.fs_stat(path.join(root_dir, ".metadata")) or search_pubspec_for_flutter_sdk()

    if is_flutter_project then
      dap.adapters.dart = {
        type = "executable",
        command = paths.flutter_bin,
        args = { "debug-adapter" },
      }
      opts.register_configurations(paths)
      local repl = require("dap.repl")
      repl.commands = vim.tbl_extend("force", repl.commands, {
        custom_commands = {
          [".hot-reload"] = function() dap.session():request("hotReload") end,
          [".hot-restart"] = function() dap.session():request("hotRestart") end,
        },
      })
    else
      dap.adapters.dart = {
        type = "executable",
        command = paths.dart_bin,
        args = { "debug_adapter" },
      }
      dap.configurations.dart = {
        {
          type = "dart",
          request = "launch",
          name = "Launch Dart",
          dartSdkPath = paths.dart_sdk,
          program = "${workspaceFolder}/bin/main.dart",
          cwd = "${workspaceFolder}",
        },
      }
    end
    if opts.exception_breakpoints and type(opts.exception_breakpoints) == "table" then
      dap.defaults.dart.exception_breakpoints = opts.exception_breakpoints
    end
  end)
end

return M
