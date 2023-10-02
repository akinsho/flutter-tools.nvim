local lazy = require("flutter-tools.lazy")
local path = lazy.require("flutter-tools.utils.path") ---@module "flutter-tools.utils.path"

local ui = require("flutter-tools.ui")

local success, dap = pcall(require, "dap")
if not success then
  ui.notify(string.format("nvim-dap is not installed!\n%s", dap), ui.ERROR)
  return
end

local M = {}

function M.select_config(paths, callback)
  local launch_configurations = {}
  local launch_configuration_count = 0
  require("flutter-tools.config").debugger.register_configurations(paths)
  local all_configurations = dap.configurations.dart
  for _, c in ipairs(all_configurations) do
    if c.request == "launch" then
      table.insert(launch_configurations, c)
      launch_configuration_count = launch_configuration_count + 1
    end
  end
  if launch_configuration_count == 0 then
    ui.notify("No launch configuration for DAP found", ui.ERROR)
    return
  elseif launch_configuration_count == 1 then
    callback(launch_configurations[1])
  else
    local launch_options = vim.tbl_map(function(item)
      return {
        text = item.name,
        type = ui.entry_type.DEBUG_CONFIG,
        data = item,
      }
    end, launch_configurations)
    ui.select({
      title = "Select launch configuration",
      lines = launch_options,
      on_select = callback,
    })
  end
end

function M.setup(config)
  local opts = config.debugger
  require("flutter-tools.executable").get(function(paths)
    local root_patterns = { ".git", "pubspec.yaml" }
    local current_dir = vim.fn.expand("%:p:h")
    local root_dir = path.find_root(root_patterns, current_dir) or current_dir
    local is_flutter_project = vim.loop.fs_stat(path.join(root_dir, ".metadata"))

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
