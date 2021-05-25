local utils = require("flutter-tools/utils")

local M = {}

local api = vim.api
local fn = vim.fn
local namespace_id = api.nvim_create_namespace("flutter_tools_popups")

local WIN_BLEND = 5

local state = {
  ---@type number[] list of open windows, so we can operate on them all
  open_windows = {},
  ---@type number
  last_opened = nil,
}

local border_chars = {
  curved = {
    "╭",
    "─",
    "╮",
    "│",
    "╯",
    "─",
    "╰",
    "│",
  },
}

function _G.__flutter_tools_close(buf)
  vim.api.nvim_buf_delete(buf, { force = true })
end

---Create a reverse look up to find a lines number in a buffer
---based on it's content
---@param buf integer
---@return table<string, integer>
local function create_buf_lookup(buf)
  local lnum_by_line = {}
  for lnum, line in ipairs(api.nvim_buf_get_lines(buf, 0, -1, false)) do
    lnum_by_line[fn.trim(line)] = lnum - 1
  end
  return lnum_by_line
end

---@param lines string[]
local function pad_lines(lines)
  local formatted = {}
  for _, line in pairs(lines) do
    table.insert(formatted, " " .. line .. " ")
  end
  return formatted
end

---@param lines string[]
local function calculate_width(lines)
  local max_width = math.ceil(vim.o.columns * 0.8)
  local max_length = 0
  for _, line in pairs(lines) do
    if #line > max_length then
      max_length = #line
    end
  end
  return max_length <= max_width and max_length or max_width
end

function M.clear_highlights(buf_id, ns_id, line_start, line_end)
  line_start = line_start or 0
  line_end = line_end or -1
  api.nvim_buf_clear_namespace(buf_id, ns_id, line_start, line_end)
end

function M.get_line_highlights(line, items, highlights)
  highlights = highlights or {}
  for _, item in ipairs(items) do
    local match_start, match_end = line:find(vim.pesc(item.word))
    if match_start and match_end then
      highlights[line] = highlights[line] or {}
      table.insert(highlights[line], {
        highlight = item.highlight,
        column_start = match_start,
        column_end = match_end + 1,
      })
    end
  end
  return highlights
end

--- @param buf_id number
--- @param lines table[]
--- @param ns_id integer
function M.add_highlights(buf_id, lines, ns_id)
  if not buf_id then
    return
  end
  ns_id = ns_id or namespace_id
  if not lines then
    return
  end
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
    if line ~= "" then
      return false
    end
  end
  return true
end

---Update notification window state
---@param win integer
local function update_win_state(win)
  state.open_windows = vim.tbl_filter(function(id)
    return id ~= win
  end, state.open_windows)
  if state.last_opened == win then
    state.last_opened = nil
  end
end

---Create a popup window to notify the user of an event
---@param lines table
---@param duration integer
function M.notify(lines, duration)
  if type(lines) ~= "table" then
    utils.echomsg([[lines passed to notify should be a list of strings]])
    return
  end
  duration = duration or 3000
  if not lines or #lines < 1 or invalid_lines(lines) then
    return
  end
  lines = pad_lines(lines)

  local row = vim.o.lines - #lines - vim.o.cmdheight - 2

  if state.last_opened then
    local config = api.nvim_win_get_config(state.last_opened)
    if config.row[false] then
      local next_row = config.row[false] - #lines - 2 -- one for padding
      -- if the next row will be outside the window then close all open windows
      -- if there is more than one, otherwise let them start to stack again from the bottom
      if next_row <= 0 then
        if #state.open_windows > 1 then
          for _, win in ipairs(state.open_windows) do
            if api.nvim_win_is_valid(win) then
              api.nvim_win_close(win, { force = true })
            end
          end
        end
      else
        row = next_row
      end
    end
  end

  local columns = vim.o.columns - vim.wo.numberwidth - 2
  local notification_width = math.ceil(columns * 0.3)
  local opts = {
    row = row,
    col = columns,
    relative = "editor",
    style = "minimal",
    width = math.min(notification_width, calculate_width(lines), 60),
    height = #lines,
    anchor = "SE",
    focusable = false,
    border = "single",
  }
  local buf = api.nvim_create_buf(false, true)
  local win = api.nvim_open_win(buf, false, opts)
  vim.wo[win].winhighlight = "NormalFloat:Normal"
  vim.wo[win].wrap = true
  api.nvim_buf_set_lines(buf, 0, -1, true, lines)

  table.insert(state.open_windows, win)
  state.last_opened = win

  vim.wo[win].winblend = WIN_BLEND
  vim.bo[buf].modifiable = false
  fn.timer_start(duration, function()
    if api.nvim_win_is_valid(win) then
      api.nvim_win_close(win, true)
    end
    update_win_state(win)
  end)
end

---@param opts table
function M.popup_create(opts)
  if not opts then
    error("An options table must be passed to popup create!")
  end
  local title, lines, on_create, highlights =
    opts.title, opts.lines, opts.on_create, opts.highlights
  if not lines or #lines < 1 or invalid_lines(lines) then
    return
  end
  lines = pad_lines(lines)
  local width = calculate_width(lines)
  local height = 10
  local buf = api.nvim_create_buf(false, true)
  lines = { title, string.rep(border_chars.curved[2], width), unpack(lines) }

  api.nvim_buf_set_lines(buf, 0, -1, true, lines)
  local win = api.nvim_open_win(buf, true, {
    row = (vim.o.lines - height) / 2,
    col = (vim.o.columns - width) / 2,
    relative = "editor",
    style = "minimal",
    width = width,
    height = height,
    border = "single",
  })

  local buf_highlights = {}
  local lookup = create_buf_lookup(buf)
  for key, value in pairs(highlights) do
    local lnum = lookup[fn.trim(key)]
    if lnum then
      for _, hl in ipairs(value) do
        hl.line_number = lnum
        buf_highlights[#buf_highlights + 1] = hl
      end
    end
  end

  M.add_highlights(buf, {
    {
      highlight = "Title",
      line_number = 0,
      column_end = #title,
      column_start = 0,
    },
    {
      highlight = "FloatBorder",
      line_number = 1,
      column_start = 0,
      column_end = -1,
    },
    unpack(buf_highlights),
  })
  vim.wo[win].winblend = WIN_BLEND
  vim.bo[buf].modifiable = false
  vim.wo[win].cursorline = true
  --- Positions cursor on the third line i.e. after the title and it's underline
  api.nvim_win_set_cursor(win, { 3, 0 })
  api.nvim_win_set_option(win, "winhighlight", "CursorLine:Visual,NormalFloat:Normal")
  api.nvim_buf_set_keymap(buf, "n", "<ESC>", ":lua __flutter_tools_close(" .. buf .. ")<CR>", {
    silent = true,
    noremap = true,
  })
  vim.cmd(string.format([[autocmd! WinLeave <buffer> silent! execute 'bw %d']], buf))
  if on_create then
    on_create(buf, win)
  end
end

function M.open_split(opts, on_open)
  local open_cmd = opts.open_cmd or "botright 30vnew"
  local name = opts.filename or "__Flutter_Tools_Unknown__"
  local filetype = opts.filetype
  vim.cmd(open_cmd)
  vim.cmd("setfiletype " .. filetype)

  local win = api.nvim_get_current_win()
  local buf = api.nvim_get_current_buf()
  local success = pcall(api.nvim_buf_set_name, buf, name)
  if not success then
    return utils.echomsg([[Sorry! a split couldn't be opened]])
  end
  vim.bo[buf].swapfile = false
  vim.bo[buf].buftype = "nofile"
  if on_open then
    on_open(buf, win)
  end
end

return M
