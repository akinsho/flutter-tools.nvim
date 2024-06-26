local M = {}

local lazy = require("flutter-tools.lazy")

local commands = lazy.require("flutter-tools.commands") ---@module "flutter-tools.commands"
local config = lazy.require("flutter-tools.config") ---@module "flutter-tools.config"
local dev_tools = lazy.require("flutter-tools.dev_tools") ---@module "flutter-tools.dev_tools"
local dap = lazy.require("flutter-tools.dap") ---@module "flutter-tools.dap"
local decorations = lazy.require("flutter-tools.decorations") ---@module "flutter-tools.decorations"
local guides = lazy.require("flutter-tools.guides") ---@module "flutter-tools.guides"
local log = lazy.require("flutter-tools.log") ---@module "flutter-tools.log"
local lsp = lazy.require("flutter-tools.lsp") ---@module "flutter-tools.lsp"
local outline = lazy.require("flutter-tools.outline") ---@module "flutter-tools.outline"
local devices = lazy.require("flutter-tools.devices") ---@module "flutter-tools.devices"
local utils = lazy.require("flutter-tools.utils") ---@module "flutter-tools.utils"

local api = vim.api

local command = function(name, callback, opts)
  api.nvim_create_user_command(name, callback, opts or {})
end

---@param opts flutter.ProjectConfig
function M.setup_project(opts) config.setup_project(opts) end

local function setup_commands()
  -- Commands
  command("FlutterRun", function(data) commands.run_command(data.args) end, { nargs = "*" })
  command("FlutterLspRestart", lsp.restart)
  command("FlutterDetach", commands.detach)
  command("FlutterReload", commands.reload)
  command("FlutterRestart", commands.restart)
  command("FlutterQuit", commands.quit)
  command("FlutterVisualDebug", commands.visual_debug)
  -- Lists
  command("FlutterDevices", devices.list_devices)
  command("FlutterEmulators", devices.list_emulators)
  --- Outline
  command("FlutterOutlineOpen", outline.open)
  command("FlutterOutlineToggle", outline.toggle)
  --- Dev tools
  command("FlutterDevTools", dev_tools.start)
  command("FlutterDevToolsActivate", dev_tools.activate)
  command("FlutterCopyProfilerUrl", commands.copy_profiler_url)
  command("FlutterOpenDevTools", commands.open_dev_tools)
  command("FlutterPubGet", commands.pub_get)
  command("FlutterPubUpgrade", function(data) commands.pub_upgrade_command(data.args) end, {
    nargs = "*",
  })
  --- Log
  command("FlutterLogToggle", log.toggle_dev_log)
  command("FlutterLogClear", log.clear)
  --- LSP
  command("FlutterSuper", lsp.dart_lsp_super)
  command("FlutterReanalyze", lsp.dart_reanalyze)
  command("FlutterRename", function() require("flutter-tools.lsp.rename").rename() end)
end

---Initialise various plugin modules
local function start()
  setup_commands()
  if config.debugger.enabled then dap.setup(config) end
  if config.widget_guides.enabled then guides.setup() end
  if config.decorations then decorations.apply(config.decorations) end
end

local AUGROUP = api.nvim_create_augroup("FlutterToolsGroup", { clear = true })
---Create autocommands for the plugin
local function setup_autocommands()
  local autocmd = api.nvim_create_autocmd

  -- delay plugin setup till we enter a dart file
  autocmd({ "BufEnter" }, {
    group = AUGROUP,
    pattern = { "*.dart", "pubspec.yaml" },
    once = true,
    callback = start,
  })

  if config.lsp.color.enabled then
    autocmd({ "BufEnter", "TextChanged", "InsertLeave" }, {
      group = AUGROUP,
      pattern = { "*.dart" },
      callback = function() lsp.document_color() end,
    })
    -- NOTE: we piggyback of this event to check for when the server is first initialized
    autocmd({ "User" }, {
      group = AUGROUP,
      pattern = utils.events.LSP_ANALYSIS_COMPLETED,
      once = true,
      callback = function() lsp.document_color() end,
    })
  end

  autocmd({ "BufWritePost" }, {
    group = AUGROUP,
    pattern = { "*.dart" },
    callback = function() commands.reload(true) end,
  })
  autocmd({ "BufWritePost" }, {
    group = AUGROUP,
    pattern = { "*/pubspec.yaml" },
    callback = function() commands.pub_get() end,
  })
  autocmd({ "BufEnter" }, {
    group = AUGROUP,
    pattern = { log.filename },
    callback = function() log.__resurrect() end,
  })
  autocmd({ "VimLeavePre" }, {
    group = AUGROUP,
    pattern = { "*" },
    callback = function() dev_tools.stop() end,
  })
end

---Entry point for this plugin
---@param user_config table
function M.setup(user_config)
  config.set(user_config)
  setup_autocommands()
end

return M
