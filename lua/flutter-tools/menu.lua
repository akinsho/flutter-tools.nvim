local lazy = require("flutter-tools.lazy")
local pickers = lazy.require("telescope.pickers") ---@module "telescope.pickers"
local snack_picker = lazy.require("snacks.picker") ---@module "snacks.picker"
local finders = lazy.require("telescope.finders") ---@module "telescope.finders"
local sorters = lazy.require("telescope.sorters") ---@module "telescope.sorters"
local actions = lazy.require("telescope.actions") ---@module "telescope.actions"
local themes = lazy.require("telescope.themes") ---@module "telescope.themes"
local action_state = lazy.require("telescope.actions.state") ---@module "telescope.actions.state"
local entry_display = lazy.require("telescope.pickers.entry_display") ---@module "telescope.pickers.entry_display"
local commands = lazy.require("flutter-tools.commands") ---@module "flutter-tools.commands"
local ui = lazy.require("flutter-tools.ui") ---@module "flutter-tools.ui"

---@alias TelescopeEntry {hint: string, label: string, command: fun(), id: integer}
---@alias CustomOptions {title: string, callback: fun(bufnr: integer)}

local M = {}

-- Accounts for the vertical padding implicit in the dropdown.
local MENU_PADDING = 4

local function execute_command(bufnr)
  local selection = action_state.get_selected_entry()
  actions.close(bufnr)
  local cmd = selection.command
  if cmd then
    local success, msg = pcall(cmd)
    if not success then ui.notify(msg, ui.ERROR) end
  end
end

local function command_entry_maker(max_width)
  local make_display = function(en)
    local has_hint = en.hint and en.hint ~= ""
    local displayer = entry_display.create({
      separator = has_hint and " • " or "",
      items = {
        { width = max_width },
        { remaining = true },
      },
    })

    local items = { { en.label, "Type" } }
    if has_hint then table.insert(items, { en.hint, ui.DIM_HL }) end
    return displayer(items)
  end
  return function(entry)
    return {
      ordinal = entry.id,
      command = entry.command,
      hint = entry.hint,
      label = entry.label,
      display = make_display,
    }
  end
end

local function get_max_length(cmds)
  local max = 0
  for _, value in ipairs(cmds) do
    max = #value.label > max and #value.label or max
  end
  return max
end

---@param items TelescopeEntry[]
---@param opts CustomOptions
---@return table
local function picker_opts(items, opts)
  local callback = opts.callback or execute_command
  return {
    prompt_title = opts.title,
    finder = finders.new_table({
      results = items,
      entry_maker = command_entry_maker(get_max_length(items)),
    }),
    sorter = sorters.get_generic_fuzzy_sorter(),
    attach_mappings = function(_, map)
      map("i", "<CR>", callback)
      map("n", "<CR>", callback)
      -- If the return value of `attach_mappings` is true, then the other
      -- default mappings are still applies.
      -- Return false if you don't want any other mappings applied.
      -- A return value _must_ be returned. It is an error to not return anything.
      return true
    end,
  }
end

---The options use to create the custom telescope picker menu's for flutter-tools
---@param items TelescopeEntry[]
---@param user_opts table?
---@param opts CustomOptions?
function M.get_config(items, user_opts, opts)
  opts = vim.tbl_deep_extend("keep", user_opts or {}, opts or {})
  return themes.get_dropdown(vim.tbl_deep_extend("keep", picker_opts(items, opts), {
    previewer = false,
    layout_config = { height = #items + MENU_PADDING },
  }))
end

local function generate_commands_list()
  local cmds = {}
  if commands.is_running() then
    cmds = {
      {
        id = "flutter-tools-hot-reload",
        label = "Hot reload",
        hint = "Reload a running flutter project",
        command = commands.reload,
      },
      {
        id = "flutter-tools-hot-restart",
        label = "Hot restart",
        hint = "Restart a running flutter project",
        command = commands.restart,
      },
      {
        id = "flutter-tools-visual-debug",
        label = "Visual Debug",
        hint = "Add the visual debugging overlay",
        command = commands.visual_debug,
      },
      {
        id = "flutter-tools-performance-overlay",
        label = "Performance Overlay",
        hint = "Toggle performance overlay",
        command = commands.performance_overlay,
      },
      {
        id = "flutter-tools-repaint-rainbow",
        label = "Repaint Rainbow",
        hint = "Toggle repaint rainbow",
        command = commands.repaint_rainbow,
      },
      {
        id = "flutter-tools-slow-animations",
        label = "Slow Animations",
        hint = "Toggle slow animations",
        command = commands.slow_animations,
      },
      {
        id = "flutter-tools-quit",
        label = "Quit",
        hint = "Quit running flutter project",
        command = commands.quit,
      },
      {
        id = "flutter-tools-detach",
        label = "Detach",
        hint = "Quit running flutter project but leave the process running",
        command = commands.detach,
      },
      {
        id = "flutter-tools-inspect-widget",
        label = "Inspect Widget",
        hint = "Toggle the widget inspector",
        command = commands.inspect_widget,
      },
      {
        id = "flutter-tools-paint-baselines",
        label = "Paint Baselines",
        hint = "Toggle paint baselines",
        command = commands.paint_baselines,
      },
    }
  else
    cmds = {
      {
        id = "flutter-tools-run",
        label = "Run",
        hint = "Start a flutter project",
        command = commands.run,
      },
    }
  end

  vim.list_extend(cmds, {
    {
      id = "flutter-tools-pub-get",
      label = "Pub get",
      hint = "Run pub get in the project directory",
      command = commands.pub_get,
    },
    {
      id = "flutter-tools-pub-upgrade",
      label = "Pub upgrade",
      hint = "Run pub upgrade in the project directory",
      command = commands.pub_upgrade,
    },
    {
      id = "flutter-tools-list-devices",
      label = "List Devices",
      hint = "Show the available physical devices",
      command = require("flutter-tools.devices").list_devices,
    },
    {
      id = "flutter-tools-list-emulators",
      label = "List Emulators",
      hint = "Show the available emulator devices",
      command = require("flutter-tools.devices").list_emulators,
    },
    {
      id = "flutter-tools-open-outline",
      label = "Open Outline",
      hint = "Show the current files widget tree",
      command = require("flutter-tools.outline").open,
    },
    {
      id = "flutter-tools-generate",
      label = "Generate ",
      hint = "Generate code",
      command = commands.generate,
    },
    {
      id = "flutter-tools-clear-dev-log",
      label = "Clear Dev Log",
      hint = "Clear previous logs in the output buffer",
      command = require("flutter-tools.log").clear,
    },
    {
      id = "flutter-tools-toggle-dev-log",
      label = "Toggle Dev Log",
      hint = "Toggle the dev log buffer",
      command = require("flutter-tools.log").toggle,
    },
    {
      id = "flutter-tools-install-app",
      label = "Install app",
      hint = "Install a Flutter app on an attached device.",
      command = require("flutter-tools.commands").install,
    },
    {
      id = "flutter-tools-uninstall-app",
      label = "Uninstall app",
      hint = "Uninstall the app if already on the device.",
      command = require("flutter-tools.commands").uninstall,
    },
  })

  local dev_tools = require("flutter-tools.dev_tools")

  if dev_tools.is_running() then
    vim.list_extend(cmds, {
      {
        id = "flutter-tools-copy-profiler-url",
        label = "Copy Profiler Url",
        hint = "Copy the profiler url to the clipboard",
        command = commands.copy_profiler_url,
      },
      {
        id = "flutter-tools-open-dev-tools",
        label = "Open Dev Tools",
        hint = "Open flutter dev tools in the browser",
        command = commands.open_dev_tools,
      },
    })
  else
    vim.list_extend(cmds, {
      {
        id = "flutter-tools-start-dev-tools",
        label = "Start Dev Tools",
        hint = "Open flutter dev tools in the browser",
        command = require("flutter-tools.dev_tools").start,
      },
    })
  end
  return cmds
end

function M.commands(opts)
  pickers
    .new(M.get_config(generate_commands_list(), opts, { title = "Flutter tools commands" }))
    :find()
end

function M.commands_snack()
  local cmds = generate_commands_list()
  for index, item in ipairs(cmds) do
    item.text = index .. ". " .. item.label
  end
  snack_picker.pick({
    title = "Flutter Tools",
    format = "text",
    autoselect = true,
    finder = function() return cmds end,
    confirm = function(picker, item)
      picker:close()
      if item and item.command then item.command() end
    end,
    layout = "select",
  })
end

local function execute_fvm_use(bufnr)
  local selection = action_state.get_selected_entry()
  actions.close(bufnr)
  local cmd = selection.command
  if cmd then
    local success, msg = pcall(cmd, selection.ordinal)
    if not success then ui.notify(msg, ui.ERROR) end
  end
end

function M.fvm(opts)
  commands.fvm_list(function(sdks)
    opts = opts and not vim.tbl_isempty(opts) and opts
      or themes.get_dropdown({
        previewer = false,
        layout_config = {
          height = #sdks + MENU_PADDING,
        },
      })

    local sdk_entries = {}
    for _, sdk in pairs(sdks) do
      table.insert(sdk_entries, {
        id = sdk.name,
        label = sdk.name,
        hint = sdk.dart_sdk_version and "(Dart SDK " .. sdk.dart_sdk_version .. ")" or "",
        command = commands.fvm_use,
      })
    end

    pickers
      .new(M.get_config(sdk_entries, opts, {
        title = "Change Flutter SDK",
        callback = execute_fvm_use,
      }))
      :find()
  end)
end

return M
