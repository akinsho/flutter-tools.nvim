local lazy = require("flutter-tools.lazy")
local ui = lazy.require("flutter-tools.ui") ---@module "flutter-tools.ui"
local dev_tools = lazy.require("flutter-tools.dev_tools") ---@module "flutter-tools.dev_tools"
local utils = lazy.require("flutter-tools.utils") ---@module "flutter-tools.utils"
local _, dap = pcall(require, "dap")

local fmt = string.format

---@type flutter.Runner
local DebuggerRunner = {}

local service_extensions_isolateid = {}
local service_extensions_state = {}

local plugin_identifier = "flutter-tools"

local command_requests = {
  restart = "hotRestart",
  reload = "hotReload",
  quit = "terminate",
  inspect = "widgetInspector",
  construction_lines = "constructionLines",
}

local service_activation_requests = {
  visual_debug = "ext.flutter.debugPaint",
}
local launch_config = nil

function DebuggerRunner:set_config(config) launch_config = config end

function DebuggerRunner:has_config() return launch_config ~= nil end

function DebuggerRunner:is_running() return dap.session() ~= nil end

function DebuggerRunner:run(paths, args, cwd, on_run_data, on_run_exit)
  if not launch_config then
    ui.notify("No launch configuration for DAP chosen", ui.ERROR)
    return
  end

  local started = false
  local before_start_logs = {}
  service_extensions_isolateid = {}
  dap.listeners.after["event_output"][plugin_identifier] = function(_, body)
    if body and body.output then
      for line in body.output:gmatch("[^\r\n]+") do
        if not started then table.insert(before_start_logs, line) end
        on_run_data(body.category == "sterr", line)
      end
    end
  end

  local handle_termination = function()
    if next(before_start_logs) ~= nil then on_run_exit(before_start_logs, args) end
  end

  dap.listeners.before["event_exited"][plugin_identifier] = function(_, _) handle_termination() end
  dap.listeners.before["event_terminated"][plugin_identifier] = function(_, _) handle_termination() end

  dap.listeners.before["event_app.started"][plugin_identifier] = function(_, _)
    started = true
    before_start_logs = {}
    utils.emit_event(utils.events.APP_STARTED)
  end

  dap.listeners.before["event_dart.debuggerUris"][plugin_identifier] = function(_, body)
    if body and body.vmServiceUri then dev_tools.register_profiler_url(body.vmServiceUri) end
  end

  dap.listeners.before["event_dart.serviceExtensionAdded"][plugin_identifier] = function(_, body)
    if body and body.extensionRPC and body.isolateId then
      service_extensions_isolateid[body.extensionRPC] = body.isolateId
    end
  end

  dap.listeners.before["event_flutter.serviceExtensionStateChanged"][plugin_identifier] = function(
    _,
    body
  )
    if body and body.extension and body.value then
      service_extensions_state[body.extension] = body.value
    end
  end

  launch_config = vim.deepcopy(launch_config)
  launch_config.cwd = cwd
  launch_config.args = vim.list_extend(launch_config.args or {}, args or {})
  launch_config.dartSdkPath = paths.dart_sdk
  launch_config.flutterSdkPath = paths.flutter_sdk
  dap.run(launch_config)
end

function DebuggerRunner:send(cmd, quiet)
  local request = command_requests[cmd]
  local service_activation_request = service_activation_requests[cmd]
  if request ~= nil then
    dap.session():request(request)
  elseif service_activation_request then
    local new_value
    if service_extensions_state[service_activation_request] == "true" then
      new_value = "false"
    else
      new_value = "true"
    end
    dap.session():request("callService", {
      method = service_activation_request,
      params = {
        enabled = new_value,
        isolateId = service_extensions_isolateid[service_activation_request],
      },
    })
  elseif not quiet then
    ui.notify("Command " .. cmd .. " is not yet implemented for DAP runner", ui.ERROR)
  end
end

function DebuggerRunner:cleanup()
  launch_config = nil
  if dap.session() then dap.terminate() end
end

return DebuggerRunner
