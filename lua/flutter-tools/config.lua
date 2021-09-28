local path = require("flutter-tools.utils.path")
local M = {}

local fn = vim.fn
local fmt = string.format

--- @param prefs table user preferences
local function validate_prefs(prefs)
  if prefs.flutter_path and prefs.flutter_lookup_cmd then
    vim.schedule(function()
      vim.notify(
        'Only one of "flutter_path" and "flutter_lookup_cmd" are required. Please remove one of the keys',
        vim.log.levels.ERROR
      )
    end)
  end
  vim.validate({
    outline = { prefs.outline, "table", true },
    dev_log = { prefs.dev_log, "table", true },
    closing_tags = { prefs.closing_tags, "table", true },
  })
end

---Create a proportional split using a percentage specified as a float
---@param percentage number
---@param fallback number
---@return string
local function get_split_cmd(percentage, fallback)
  return string.format("botright %dvnew", math.max(vim.o.columns * percentage, fallback))
end

local function get_default_lookup()
  local exepath = fn.exepath("flutter")
  local is_snap_installation = exepath and exepath:match("snap") or false
  return (path.is_linux and is_snap_installation) and "flutter sdk-path" or nil
end

M.debug_levels = {
  DEBUG = 1,
  WARN = 2,
}

local defaults = {
  flutter_path = nil,
  flutter_lookup_cmd = get_default_lookup(),
  widget_guides = {
    enabled = false,
    debug = false,
  },
  ui = {
    border = "single",
  },
  decorations = {
    statusline = {
      app_version = false,
      device = false,
    },
  },
  debugger = {
    enabled = false,
  },
  closing_tags = {
    highlight = "Comment",
    format = "// %s",
    enabled = true,
  },
  lsp = {
    debug = M.debug_levels.WARN,
  },
  outline = setmetatable({
    auto_open = false,
  }, {
    __index = function(_, k)
      return k == "open_cmd" and get_split_cmd(0.3, 40) or nil
    end,
  }),
  dev_log = setmetatable({}, {
    __index = function(_, k)
      return k == "open_cmd" and get_split_cmd(0.4, 50) or nil
    end,
  }),
  dev_tools = {
    autostart = false,
    auto_open_browser = false,
  },
}

local deprecations = {
  flutter_outline = {
    fallback = "widget_guides",
    message = "please use 'widget_guides' instead",
  },
}

local function handle_deprecation(key, value, config)
  local utils = require("flutter-tools.utils")
  local deprecation = deprecations[key]
  if not deprecation then
    return
  end
  vim.defer_fn(function()
    utils.notify(fmt("%s is deprecated: %s", key, deprecation.message), utils.L.WARN)
  end, 1000)
  if deprecation.fallback then
    config[deprecation.fallback] = value
  end
end

local config = setmetatable({}, { __index = defaults })

---Get the configuration or just a key of the config
---@param key string
---@return any
function M.get(key)
  if key then
    return config[key]
  end
  return config
end

function M.set(user_config)
  if not user_config or type(user_config) ~= "table" then
    return config
  end
  validate_prefs(user_config)
  for key, value in pairs(user_config) do
    handle_deprecation(key, value, user_config)
    if user_config[key] and type(user_config[key]) == "table" then
      setmetatable(user_config[key], { __index = defaults[key] })
    end
  end
  config = setmetatable(user_config, { __index = defaults })
  return config
end

return M
