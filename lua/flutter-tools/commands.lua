local lazy = require("flutter-tools.lazy")
local Job = require("plenary.job")
local ui = lazy.require("flutter-tools.ui") ---@module "flutter-tools.ui"
local utils = lazy.require("flutter-tools.utils") ---@module "flutter-tools.utils"
local devices = lazy.require("flutter-tools.devices") ---@module "flutter-tools.devices"
local config = lazy.require("flutter-tools.config") ---@module "flutter-tools.config"
local executable = lazy.require("flutter-tools.executable") ---@module "flutter-tools.executable"
local dev_tools = lazy.require("flutter-tools.dev_tools") ---@module   "flutter-tools.dev_tools"
local lsp = lazy.require("flutter-tools.lsp") ---@module "flutter-tools.lsp"
local job_runner = lazy.require("flutter-tools.runners.job_runner") ---@module "flutter-tools.runners.job_runner"
local debugger_runner = lazy.require("flutter-tools.runners.debugger_runner") ---@module "flutter-tools.runners.debugger_runner"
local dev_log = lazy.require("flutter-tools.log") ---@module "flutter-tools.log"

local M = {}

---@alias RunOpts {cli_args: string[]?, args: string[]?, device: Device?}

---@type table?
local current_device = nil

---@class flutter.Runner
---@field is_running fun(runner: flutter.Runner):boolean
---@field run fun(runner: flutter.Runner, paths:table, args:table, cwd:string, on_run_data:fun(is_err:boolean, data:string), on_run_exit:fun(data:string[], args: table))
---@field cleanup fun(funner: flutter.Runner)
---@field send fun(runner: flutter.Runner, cmd:string, quiet: boolean?)

---@type flutter.Runner?
local runner = nil

local function use_debugger_runner()
  local dap_ok, dap = pcall(require, "dap")
  if not config.debugger.run_via_dap then return false end
  if dap_ok then return true end
  ui.notify(
    utils.join({ "debugger runner was request but nvim-dap is not installed!", dap }),
    ui.ERROR
  )
  return false
end

function M.current_device() return current_device end

function M.is_running() return runner ~= nil and runner:is_running() end

local function match_error_string(line)
  if not line then return false end
  -- match the error string if no devices are setup
  if line:match("No supported devices connected") ~= nil then
    -- match the error string returned if multiple devices are matched
    return true, "Choose a device"
  elseif line:match("More than one device connected") ~= nil then
    return true, "Choose a device"
  end
end

---@param lines string[]
---@return boolean, string?
local function has_recoverable_error(lines)
  for _, line in pairs(lines) do
    local match, msg = match_error_string(line)
    if match then return match, msg end
  end
  return false, nil
end

---Handle output from flutter run command
---@param is_err boolean if this is stdout or stderr
local function on_run_data(is_err, data)
  if is_err and config.dev_log.notify_errors then ui.notify(data, ui.ERROR, { timeout = 5000 }) end
  dev_log.log(data, config.dev_log)
end

local function shutdown()
  if runner then runner:cleanup() end
  runner = nil
  current_device = nil
  utils.emit_event(utils.events.PROJECT_CONFIG_CHANGED)
  dev_tools.on_flutter_shutdown()
end

---Handle a finished flutter run command
---@param result string[]
local function on_run_exit(result, cli_args)
  local matched_error, msg = has_recoverable_error(result)
  if matched_error then
    local lines = devices.to_selection_entries(result)
    ui.select({
      title = ("Flutter run (%s)"):format(msg),
      lines = lines,
      on_select = function(device) devices.select_device(device, cli_args) end,
    })
  end
  shutdown()
end

--- Take arguments from the commandline and pass
--- them to the run command
---@param args string
function M.run_command(args)
  args = args and args ~= "" and vim.split(args, " ") or nil
  M.run({ args = args })
end

---@param callback fun(project_config: flutter.ProjectConfig?)
local function select_project_config(callback)
  local project_config = config.project --[=[@as flutter.ProjectConfig[]]=]
  if #project_config <= 1 then
    utils.emit_event(utils.events.PROJECT_CONFIG_CHANGED, { data = project_config[1] })
    return callback(project_config[1])
  end
  vim.ui.select(project_config, {
    prompt = "Select a project configuration",
    format_item = function(item)
      if item.name then return item.name end
      return vim.inspect(item)
    end,
  }, function(selected)
    if selected then
      utils.emit_event(utils.events.PROJECT_CONFIG_CHANGED, { data = selected })
      callback(selected)
    end
  end)
end

---@param opts RunOpts
---@param conf flutter.ProjectConfig?
---@return string[]
local function get_run_args(opts, conf)
  local args = {}
  local cmd_args = opts.args
  local device = conf and conf.device or (opts.device and opts.device.id)
  local flavor = conf and conf.flavor
  local target = conf and conf.target
  local dart_defines = conf and conf.dart_define
  local dart_define_from_file = conf and conf.dart_define_from_file
  local dev_url = dev_tools.get_url()

  if not use_debugger_runner() then vim.list_extend(args, { "run" }) end
  if not cmd_args and device then vim.list_extend(args, { "-d", device }) end
  if cmd_args then vim.list_extend(args, cmd_args) end
  if flavor then vim.list_extend(args, { "--flavor", flavor }) end
  if target then vim.list_extend(args, { "--target", target }) end
  if dart_define_from_file then
    vim.list_extend(args, { "--dart-define-from-file", dart_define_from_file })
  end
  if dart_defines then
    for key, value in pairs(dart_defines) do
      vim.list_extend(args, { "--dart-define", ("%s=%s"):format(key, value) })
    end
  end
  if dev_url then vim.list_extend(args, { "--devtools-server-address", dev_url }) end
  return args
end

---@param opts RunOpts
---@param project_conf flutter.ProjectConfig?
local function run(opts, project_conf)
  opts = opts or {}
  executable.get(function(paths)
    local args = opts.cli_args or get_run_args(opts, project_conf)
    ui.notify("Starting flutter project...")
    if use_debugger_runner() then
      if not debugger_runner.has_config() then
        require("flutter-tools.dap")
            .select_config(paths, function(launch_config)
              debugger_runner:set_config(launch_config)
              if not launch_config.deviceId then
                -- if no device set in launch_config, get one to avoid selecting config twice
                devices.list_devices()
                return
              end
              run(opts, project_conf)
            end)
        return
      end
      runner = debugger_runner
    else
      runner = job_runner
    end
    runner:run(paths, args, lsp.get_lsp_root_dir(), on_run_data, on_run_exit)
  end)
end

---Run the flutter application
---@param opts RunOpts
function M.run(opts)
  if M.is_running() then return ui.notify("Flutter is already running!") end
  select_project_config(function(project_conf) run(opts, project_conf) end)
end

---@param cmd string
---@param quiet boolean?
---@param on_send function|nil
local function send(cmd, quiet, on_send)
  if M.is_running() and runner then
    runner:send(cmd, quiet)
    if on_send then on_send() end
  elseif not quiet then
    ui.notify("Sorry! Flutter is not running")
  end
end

---@param quiet boolean?
function M.reload(quiet) send("reload", quiet) end

---@param quiet boolean?
function M.restart(quiet)
  send("restart", quiet, function()
    if not quiet then ui.notify("Restarting...", nil, { timeout = 1500 }) end
  end)
end

---@param quiet boolean?
function M.quit(quiet)
  send("quit", quiet, function()
    if not quiet then
      ui.notify("Closing flutter application...", nil, { timeout = 1500 })
      shutdown()
    end
  end)
end

---@param quiet boolean?
function M.visual_debug(quiet) send("visual_debug", quiet) end

---@param quiet boolean?
function M.detach(quiet) send("detach", quiet) end

function M.copy_profiler_url()
  if not M.is_running() then
    ui.notify("You must run the app first!")
    return
  end

  local url, is_running = dev_tools.get_profiler_url()

  if url then
    vim.cmd("let @+='" .. url .. "'")
    ui.notify("Profiler url copied to clipboard!")
  elseif is_running then
    ui.notify("Wait while the app starts", "please try again later")
  else
    ui.notify("You must start the DevTools server first!")
  end
end

---@param quiet boolean?
function M.open_dev_tools(quiet) send("open_dev_tools", quiet) end

---@param quiet boolean
function M.generate(quiet) send("generate", quiet) end

---@param quiet boolean
function M.widget_inspector(quiet) send("inspect", quiet) end

---@param quiet boolean
function M.construction_lines(quiet) send("construction_lines", quiet) end

-----------------------------------------------------------------------------//
-- Pub commands
-----------------------------------------------------------------------------//
---Print result of running pub get
---@param result string[]
local function on_pub_get(result, err)
  local timeout = err and 10000 or nil
  ui.notify(utils.join(result), nil, { timeout = timeout })
end

---@type Job?
local pub_get_job = nil

function M.pub_get()
  if not pub_get_job then
    executable.flutter(function(cmd)
      pub_get_job = Job:new({
        command = cmd,
        args = { "pub", "get" },
        -- stylua: ignore
        cwd = lsp.get_lsp_root_dir() --[[@as string]],
      })
      pub_get_job:after_success(vim.schedule_wrap(function(j)
        on_pub_get(j:result())
        pub_get_job = nil
      end))
      pub_get_job:after_failure(vim.schedule_wrap(function(j)
        on_pub_get(j:stderr_result(), true)
        pub_get_job = nil
      end))
      pub_get_job:start()
    end)
  end
end

---@type Job?
local pub_upgrade_job = nil

--- Take arguments from the commandline and pass
--- them to the pub upgrade command
---@param args string
function M.pub_upgrade_command(args)
  args = args and args ~= "" and vim.split(args, " ") or nil
  M.pub_upgrade(args)
end

function M.pub_upgrade(cmd_args)
  if not pub_upgrade_job then
    executable.flutter(function(cmd)
      local notify_timeout = 10000
      local args = { "pub", "upgrade" }
      if cmd_args then vim.list_extend(args, cmd_args) end
      pub_upgrade_job = Job:new({
        command = cmd,
        args = args,
        -- stylua: ignore
        cwd = lsp.get_lsp_root_dir() --[[@as string]],
      })
      pub_upgrade_job:after_success(vim.schedule_wrap(function(j)
        ui.notify(utils.join(j:result()), nil, { timeout = notify_timeout })
        pub_upgrade_job = nil
      end))
      pub_upgrade_job:after_failure(vim.schedule_wrap(function(j)
        ui.notify(utils.join(j:stderr_result()), nil, { timeout = notify_timeout })
        pub_upgrade_job = nil
      end))
      pub_upgrade_job:start()
    end)
  end
end

-----------------------------------------------------------------------------//
-- FVM commands
-----------------------------------------------------------------------------//

---@type Job?
local fvm_list_job = nil

--- Returns table<{name: string, status: active|global|nil}>
function M.fvm_list(callback)
  if not fvm_list_job then
    -- Example output:
    --
    -- Cache Directory:  /Users/rjm/fvm/versions
    --
    -- master (active)
    -- beta
    -- stable (global)
    fvm_list_job = Job:new({ command = "fvm", args = { "list" } })

    fvm_list_job:after_success(vim.schedule_wrap(function(j)
      local out = j:result()
      local sdks_out = { unpack(out, 3, #out) }

      local sdks = {}
      for _, sdk_out in pairs(sdks_out) do
        -- matches: "<name> (<status>)"
        local name, status = sdk_out:match("(.*)%s%((%w+)%)")
        name = name or sdk_out
        table.insert(sdks, { name = name, status = status })
      end

      callback(sdks)
      fvm_list_job = nil
    end))

    fvm_list_job:after_failure(vim.schedule_wrap(function(j)
      ui.notify(utils.join(j:stderr_result()), ui.ERROR)
      fvm_list_job = nil
    end))

    fvm_list_job:start()
  end
end

---@type Job?
local fvm_use_job = nil

function M.fvm_use(sdk_name)
  if not fvm_use_job then
    fvm_use_job = Job:new({ command = "fvm", args = { "use", sdk_name } })

    fvm_use_job:after_success(vim.schedule_wrap(function(j)
      ui.notify(utils.join(j:result()))
      shutdown()
      executable.reset_paths()
      lsp.restart()

      fvm_use_job = nil
    end))

    fvm_use_job:after_failure(vim.schedule_wrap(function(j)
      ui.notify(utils.join(j:result()), nil, { timeout = 10000 }) -- FVM doesn't output to stderr, nice
      fvm_use_job = nil
    end))

    fvm_use_job:start()
  end
end

if __TEST then
  M.__run = run
  M.__get_run_args = get_run_args
end

return M
