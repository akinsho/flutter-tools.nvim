local M = {}
local fn = vim.fn
local api = vim.api
local fmt = string.format

-- FIXME: remove this when lua autocommands are officially supported
-- Global store of callback for autocommand (and eventually mappings)
_G.__flutter_tools_callbacks = __flutter_tools_callbacks or {}

---@param name string
---@return string
function M.display_name(name, platform)
  if not name then
    return ""
  end
  local symbol = "•"
  return symbol
    .. " "
    .. name
    .. (platform and platform ~= "" and (" " .. symbol .. " ") .. platform or "")
end

---Create a neovim command
---@param name string
---@param rhs string
---@param modifiers string[]?
function M.command(name, rhs, modifiers)
  modifiers = modifiers or {}
  local nargs = modifiers and modifiers.nargs or 0
  vim.cmd(fmt("command! -nargs=%s %s %s", nargs, name, rhs))
end

--- if every item in a table is an empty value return true
function M.list_is_empty(tbl)
  if not tbl then
    return true
  end
  return table.concat(tbl) == ""
end

function M.buf_valid(bufnr, name)
  local target = bufnr or name
  if not target then
    return false
  end
  if bufnr then
    return api.nvim_buf_is_loaded(bufnr)
  end
  return vim.fn.bufexists(target) > 0
end

---Add a function to the global callback map
---@param f function
---@return number
local function _create(f)
  table.insert(__flutter_tools_callbacks, f)
  return #__flutter_tools_callbacks
end

function M._execute(id, args)
  __flutter_tools_callbacks[id](args)
end

---Create a mapping
---@param mode string
---@param lhs string
---@param rhs string | function
---@param opts table
function M.map(mode, lhs, rhs, opts)
  -- add functions to a global table keyed by their index
  if type(rhs) == "function" then
    local fn_id = _create(rhs)
    rhs = string.format("<cmd>lua require('flutter-tools.utils')._execute(%s)<CR>", fn_id)
  end
  local buffer = opts.buffer
  opts.silent = opts.silent ~= nil and opts.silent or true
  opts.noremap = opts.noremap ~= nil and opts.noremap or true
  opts.buffer = nil
  if buffer and type(buffer) == "number" then
    api.nvim_buf_set_keymap(buffer, mode, lhs, rhs, opts)
  else
    api.nvim_set_keymap(mode, lhs, rhs, opts)
  end
end

---@class FlutterAutocmd
---@field events string[] list of autocommand events
---@field targets string[] list of autocommand patterns
---@field modifiers string[] e.g. nested, once
---@field command string | function

---Create an autocommand
---@param name string
---@param commands FlutterAutocmd[]
function M.augroup(name, commands)
  vim.cmd("augroup " .. name)
  vim.cmd("autocmd!")
  for _, c in ipairs(commands) do
    local command = c.command
    if type(command) == "function" then
      local fn_id = _create(command)
      command = fmt("lua require('flutter-tools.utils')._execute(%s)", fn_id)
    end
    vim.cmd(
      string.format(
        "autocmd %s %s %s %s",
        table.concat(c.events, ","),
        table.concat(c.targets or {}, ","),
        table.concat(c.modifiers or {}, " "),
        command
      )
    )
  end
  vim.cmd("augroup END")
end

---Add a highlight group and an accompanying autocommand to refresh it
---if the colorscheme changes
---@param name string
---@param opts table
function M.highlight(name, opts)
  local hls = {}
  for k, v in pairs(opts) do
    table.insert(hls, fmt("%s=%s", k, v))
  end
  local hl_cmd = fmt("highlight! %s %s", name, table.concat(hls, " "))
  vim.cmd(hl_cmd)
  M.augroup(name .. "Refresh", {
    {
      events = { "ColorScheme" },
      targets = { "*" },
      command = hl_cmd,
    },
  })
end

function M.fold(accumulator, callback, list)
  for _, v in ipairs(list) do
    accumulator = callback(accumulator, v)
  end
  return accumulator
end

---Find an item in a list based on a compare function
---@generic T
---@param compare fun(item: T): boolean
---@param list `T`
---@return `T`
function M.find(list, compare)
  for _, item in ipairs(list) do
    if compare(item) then
      return item
    end
  end
end

---Merge two table but maintain metatables
---Priority is given to the second table
--- FIXME: this does not copy metatables
---@param t1 table
---@param t2 table
---@param skip string[]?
---@return table
function M.merge(t1, t2, skip)
  for k, v in pairs(t2) do
    if not skip or not vim.tbl_contains(skip, k) then
      if (type(v) == "table") and (type(t1[k] or false) == "table") then
        M.merge(t1[k], t2[k])
      else
        t1[k] = v
      end
    end
  end
  return t1
end

function M.remove_newlines(str)
  if not str or type(str) ~= "string" then
    return str
  end
  return str:gsub("[\n\r]", "")
end

function M.executable(bin)
  return fn.executable(bin) > 0
end

---Get the attribute value of a specified highlight
---@param name string
---@param attribute string
---@return string
function M.get_hl(name, attribute)
  return fn.synIDattr(fn.hlID(name), attribute)
end

function M.open_command()
  local path = require("flutter-tools.utils.path")
  if path.is_mac then
    return "open"
  end
  if path.is_linux then
    return "xdg-open"
  end
  if path.is_windows then
    return "explorer"
  end
  return nil, nil
end

---Create an lsp handler compatible with the new handler signature
---@see: https://github.com/neovim/neovim/pull/15504/
---@param func function
---@return function
function M.lsp_handler(func)
  return function(...)
    local config_or_client_id = select(4, ...)
    local is_new = type(config_or_client_id) ~= "number"
    if is_new then
      func(...)
    else
      local err = select(1, ...)
      local method = select(2, ...)
      local result = select(3, ...)
      local client_id = select(4, ...)
      local bufnr = select(5, ...)
      local config = select(6, ...)
      func(err, result, { method = method, client_id = client_id, bufnr = bufnr }, config)
    end
  end
end

return M
