local lazy = require("flutter-tools.lazy")
local ui = lazy.require("flutter-tools.ui") ---@module "flutter-tools.ui"
local utils = lazy.require("flutter-tools.utils") ---@module "flutter-tools.utils"
local config = lazy.require("flutter-tools.config") ---@module "flutter-tools.config"

local api = vim.api
local fn = vim.fn
local fmt = string.format

local M = {
  --@type integer
  buf = nil,
  --@type integer
  win = nil,
}

M.filename = "__FLUTTER_DEV_LOG__"

--- check if the buffer exists if does and we
--- lost track of it's buffer number re-assign it
local function exists()
  local is_valid = utils.buf_valid(M.buf, M.filename)
  if is_valid and not M.buf then M.buf = vim.fn.bufnr(M.filename) end
  return is_valid
end


local function is_open()
  local wins = fn.win_findbuf(M.buf)
  return wins and #wins > 0
end

local function delete_dev_log()
  M.buf = nil
  M.win = nil
end

local function close_dev_log()
  if api.nvim_win_is_valid(M.win) then api.nvim_win_close(M.win, true) end
end

local function open_dev_log()
  local opts = {
    filename = M.filename,
    filetype = "log",
    open_cmd = config.dev_log.open_cmd,
  }
  ui.open_win(opts, function(buf, win)
    if not buf then
      ui.notify("Failed to open the dev log as the buffer could not be found", ui.ERROR)
      return
    end
    M.buf = buf
    M.win = win

    api.nvim_create_autocmd("BufWipeout", {
      buffer = buf,
      callback = delete_dev_log,
    })
  end)
end

function M.toggle_dev_log()
  if is_open() then
    close_dev_log()
  else
    open_dev_log()
  end
end

function M.get_content()
  if M.buf then return api.nvim_buf_get_lines(M.buf, 0, -1, false) end
end

---Auto-scroll the log buffer to the end of the output
---@param buf integer
---@param target_win integer
local function autoscroll(buf, target_win)
  local win = utils.find(
    api.nvim_tabpage_list_wins(0),
    function(item) return item == target_win end
  )
  if not win then return end
  -- if the dev log is focused don't scroll it as it will block the user from perusing
  if api.nvim_get_current_win() == win then return end
  local buf_length = api.nvim_buf_line_count(buf)
  local success, err = pcall(api.nvim_win_set_cursor, win, { buf_length, 0 })
  if not success then
    ui.notify(fmt("Failed to set cursor for log window %s: %s", win, err), ui.ERROR, {
      once = true,
    })
  end
end

---Add lines to a buffer
---@param buf number
---@param lines string[]
local function append(buf, lines)
  vim.bo[buf].modifiable = true
  api.nvim_buf_set_lines(M.buf, -1, -1, true, lines)
  vim.bo[buf].modifiable = false
end

--- Open a log showing the output from a command
--- in this case flutter run
---@param data string
---@param opts table
function M.log(data, opts)
  if opts.enabled then
    if not exists() then open_dev_log(opts) end
    append(M.buf, { data })
    autoscroll(M.buf, M.win)
  end
end

function M.__resurrect()
  local buf = api.nvim_get_current_buf()
  vim.cmd("setfiletype log")
  vim.bo[buf].modifiable = false
  vim.bo[buf].modified = false
  vim.bo[buf].buftype = "nofile"
end

function M.clear()
  if api.nvim_buf_is_valid(M.buf) then
    vim.bo[M.buf].modifiable = true
    api.nvim_buf_set_lines(M.buf, 0, -1, false, {})
    vim.bo[M.buf].modifiable = false
  end
end

return M
