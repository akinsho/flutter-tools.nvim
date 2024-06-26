local utils = require("flutter-tools.utils")
local fmt = string.format

---@enum EntryType
local entry_type = {
  CODE_ACTION = 1,
  DEVICE = 2,
}

---@generic T
---@alias SelectionEntry {text: string, type: EntryType, data: T}

---@enum
local M = {
  ERROR = vim.log.levels.ERROR,
  DEBUG = vim.log.levels.DEBUG,
  INFO = vim.log.levels.INFO,
  TRACE = vim.log.levels.TRACE,
  WARN = vim.log.levels.WARN,
}

local api = vim.api
local namespace_id = api.nvim_create_namespace("flutter_tools_popups")
M.entry_type = entry_type

function M.clear_highlights(buf_id, ns_id, line_start, line_end)
  line_start = line_start or 0
  line_end = line_end or -1
  api.nvim_buf_clear_namespace(buf_id, ns_id, line_start, line_end)
end

--- @param buf_id number
--- @param lines table[]
--- @param ns_id integer?
function M.add_highlights(buf_id, lines, ns_id)
  if not buf_id then return end
  ns_id = ns_id or namespace_id
  if not lines then return end
  for _, line in ipairs(lines) do
    api.nvim_buf_add_highlight(
      buf_id,
      ns_id,
      line.highlight,
      line.line_number,
      line.column_start,
      line.column_end
    )
  end
end

--- check if there is a single non empty line
--- in the list of lines
--- @param lines table
local function invalid_lines(lines)
  for _, line in pairs(lines) do
    if line ~= "" then return false end
  end
  return true
end

---Post a message to UI so the user knows something has occurred.
---@param msg string | string[]
---@param level integer
---@param opts {timeout: number, once: boolean}?
M.notify = function(msg, level, opts)
  opts, level = opts or {}, level or M.INFO
  msg = type(msg) == "table" and utils.join(msg) or msg
  if msg == "" then return end
  local args = { title = "Flutter tools", timeout = opts.timeout, icon = "" }
  if opts.once then
    vim.notify_once(msg, level, args)
  else
    vim.notify(msg, level, args)
  end
end

---@param opts table
---@param on_confirm function
M.input = function(opts, on_confirm) vim.ui.input(opts, on_confirm) end

--- @param items SelectionEntry[]
--- @param title string
--- @param on_select fun(item: SelectionEntry)
local function get_telescope_picker_config(items, title, on_select)
  local ok = pcall(require, "telescope")
  if not ok then return end

  local filtered = vim.tbl_filter(function(value) return value.data ~= nil end, items) --[[@as SelectionEntry[]]

  return require("flutter-tools.menu").get_config(
    vim.tbl_map(function(item)
      local data = item.data
      if item.type == entry_type.CODE_ACTION then
        return {
          id = data.title,
          label = data.title,
          command = function() on_select(data) end,
        }
      elseif item.type == entry_type.DEVICE then
        return {
          id = data.id,
          label = data.name,
          hint = data.platform,
          command = function() on_select(data) end,
        }
      end
    end, filtered),
    { title = title }
  )
end

---@alias PopupOpts {title:string, lines: SelectionEntry[], on_select: fun(item: SelectionEntry)}
---@param opts PopupOpts
function M.select(opts)
  assert(opts ~= nil, "An options table must be passed to popup create!")
  local title, lines, on_select = opts.title, opts.lines, opts.on_select
  if not lines or #lines < 1 or invalid_lines(lines) then return end

  vim.ui.select(lines, {
    prompt = title,
    kind = "flutter-tools",
    format_item = function(item) return item.text end,
    -- custom key for dressing.nvim
    telescope = get_telescope_picker_config(lines, title, on_select),
  }, function(item)
    if not item then return end
    on_select(item.data)
  end)
end

---Create a split window
---@param opts table
---@param on_open fun(buf: integer, win: integer)
---@return nil
function M.open_win(opts, on_open)
  local open_cmd = opts.open_cmd or "botright 30vsplit"
  local name = opts.filename or "__Flutter_Tools_Unknown__"
  open_cmd = fmt("%s %s", open_cmd, name)
  vim.cmd(open_cmd)

  local win = api.nvim_get_current_win()
  local buf = api.nvim_get_current_buf()
  vim.bo[buf].filetype = opts.filetype
  vim.bo[buf].swapfile = false
  vim.bo[buf].buftype = "nofile"
  if on_open then on_open(buf, win) end
end

return M
