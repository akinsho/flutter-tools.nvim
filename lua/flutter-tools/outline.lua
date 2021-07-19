local ui = require("flutter-tools.ui")
local utils = require("flutter-tools.utils")
local config = require("flutter-tools.config")

local api = vim.api
local fn = vim.fn
local outline_filename = "Flutter Outline"
local outline_filetype = "flutterToolsOutline"

local M = setmetatable({}, {
  __index = function(_, k)
    --- if the buffer of the outline file is nil but it *might* exist
    --- we default to also checking if any file with a similar name exists
    -- if so we return it's buffer number
    if k == "buf" then
      local buf = fn.bufnr(outline_filename)
      return buf >= 0 and buf or nil
    end
    return nil
  end,
})

-----------------------------------------------------------------------------//
-- Namespaces
-----------------------------------------------------------------------------//
local outline_ns_id = api.nvim_create_namespace("flutter_tools_outline_selected_item")

-----------------------------------------------------------------------------//
-- Icons
-----------------------------------------------------------------------------//

local markers = {
  bottom = "└",
  middle = "├",
  vertical = "│",
  horizontal = "─",
}

local icons = setmetatable({
  TOP_LEVEL_VARIABLE = "",
  CLASS = "",
  FIELD = "綠",
  CONSTRUCTOR = "",
  CONSTRUCTOR_INVOCATION = "ﰪ",
  FUNCTION = "ƒ",
  METHOD = "",
  GETTER = "ྟ",
  ENUM = "",
  ENUM_CONSTANT = "",
  DEFAULT = "",
}, {
  __index = function(t, _)
    return t.DEFAULT
  end,
})

local hl_prefix = "FlutterToolsOutline"

local icon_highlights = {
  [icons.TOP_LEVEL_VARIABLE] = {
    name = hl_prefix .. "TopLevelVar",
    link = "Identifier",
  },
  [icons.CLASS] = { name = hl_prefix .. "Class", link = "Type" },
  [icons.FIELD] = { name = hl_prefix .. "Field", link = "Identifier" },
  [icons.CONSTRUCTOR] = {
    name = hl_prefix .. "Constructor",
    link = "Identifier",
  },
  [icons.CONSTRUCTOR_INVOCATION] = {
    name = hl_prefix .. "ConstructorInvocation",
    link = "Special",
  },
  [icons.FUNCTION] = { name = hl_prefix .. "Function", link = "Function" },
  [icons.METHOD] = { name = hl_prefix .. "Method", link = "Function" },
  [icons.GETTER] = { name = hl_prefix .. "Getter", link = "Function" },
  [icons.ENUM] = { name = hl_prefix .. "Enum", link = "Type" },
  [icons.ENUM_CONSTANT] = {
    name = hl_prefix .. "EnumConstant",
    link = "Type",
  },
  [icons.DEFAULT] = {
    name = hl_prefix .. "Default",
    link = "Comment",
  },
}

-----------------------------------------------------------------------------//
-- State
-----------------------------------------------------------------------------//
M.buf = nil
M.outlines = setmetatable({}, {
  __index = function()
    return {}
  end,
})
M.options = {}

---@param name string
---@param value string
---@param group string
local function highlight_item(name, value, group)
  vim.cmd(string.format([[syntax match %s /%s/]], name, value))
  vim.cmd("highlight default link " .. name .. " " .. group)
end

local function set_outline_highlights()
  vim.cmd("highlight default link " .. hl_prefix .. "SelectedOutlineItem Search")
  for key, value in pairs(markers) do
    highlight_item(hl_prefix .. key, value, "Whitespace")
  end
  for icon, hl in pairs(icon_highlights) do
    highlight_item(hl.name, icon, hl.link)
  end
end

---@param list table
---@param highlights table
---@param item string
---@param hl string
---@param length number
local function add_segment(list, highlights, item, hl, length, pos)
  if item and item ~= "" then
    local item_length = #item
    local new_length = item_length + length
    table.insert(highlights, {
      value = item,
      highlight = hl,
      column_start = length + 1,
      column_end = new_length + 1,
    })
    if pos then
      table.insert(list, pos, item)
    else
      table.insert(list, item)
    end
    length = new_length
  end
  return length
end

---@param result table
---@param node table
---@param indent string
---@param marker string
local function parse_outline(result, node, indent, marker)
  indent = indent or ""
  marker = marker or ""
  if not node then
    return
  end
  local range = node.codeRange
  local element = node.element or {}
  local text = {}
  local icon = icons[element.kind]
  local display_str = { indent, marker, icon }

  local hl = {}
  local length = #table.concat(display_str, " ")

  --- NOTE highlights are byte indexed
  --- so use "#" operator to get the byte count
  local return_type = element.returnType and element.returnType .. " "
  length = add_segment(text, hl, return_type, "Comment", length)
  length = add_segment(text, hl, element.name, "None", length)
  length = add_segment(text, hl, element.typeParameters, "Type", length)
  length = add_segment(text, hl, element.parameters, "Bold", length)

  table.insert(display_str, table.concat(text, ""))
  local content = table.concat(display_str, " ")

  table.insert(result, {
    hl = hl,
    -- this number might be required to be 1 or 0 based
    -- based on the api call using it as row, col api functions
    -- can be (1, 0) based. It is stored as 0 based as this is the
    -- most common requirement but must be one based when manipulating
    -- the cursor
    lnum = #result,
    buf_start = #indent,
    buf_end = #content,
    start_line = range.start.line,
    start_col = range.start.character - 1,
    end_line = range["end"].line,
    end_col = range["end"].character - 1,
    name = element.name,
    text = content,
  })

  local children = node.children
  if not children or vim.tbl_isempty(children) then
    return
  end

  local parent_marker = marker == markers.middle and markers.vertical or " "
  indent = indent .. " " .. parent_marker
  for index, child in ipairs(children) do
    local new_marker = index == #children and markers.bottom or markers.middle
    parse_outline(result, child, indent, new_marker)
  end
end

local function get_display_props(items)
  local lines = {}
  local highlights = {}
  for _, item in ipairs(items) do
    if item.hl then
      for _, hl in ipairs(item.hl) do
        hl.line_number = item.lnum
        table.insert(highlights, hl)
      end
    end
    table.insert(lines, item.text)
  end
  return lines, highlights
end

local function setup_autocommands()
  utils.augroup("FlutterToolsOutline", {
    {
      events = { "User FlutterOutlineChanged" },
      command = [[lua __flutter_tools_refresh_outline()]],
    },
    {
      events = { "CursorHold" },
      targets = { "*.dart" },
      command = [[lua __flutter_tools_set_current_item()]],
    },
    {
      events = { "BufEnter" },
      targets = { "*.dart" },
      command = [[doautocmd User FlutterOutlineChanged]],
    },
  })
end

---@param lines table
---@param highlights table
local function setup_outline_window(lines, highlights)
  return function(buf, win)
    M.buf = buf
    vim.wo[win].number = false
    vim.wo[win].relativenumber = false
    vim.wo[win].wrap = false
    vim.bo[buf].buflisted = false
    vim.bo[buf].bufhidden = "wipe"
    vim.bo[buf].buftype = "nofile"
    vim.wo[win].winfixwidth = true

    api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false

    set_outline_highlights()

    if highlights and not vim.tbl_isempty(highlights) then
      ui.add_highlights(M.buf, highlights)
    end

    api.nvim_buf_set_keymap(
      buf,
      "n",
      "q",
      "<Cmd>bw!<CR>",
      { noremap = true, nowait = true, silent = true }
    )

    api.nvim_buf_set_keymap(buf, "n", "<CR>", [[<Cmd>lua __flutter_tools_select_outline_item()<CR>]], {
      noremap = true,
      nowait = true,
      silent = true,
    })
    setup_autocommands()
  end
end

---@param buf integer the buf number
---@param lines table the lines to append
---@param highlights table the highlights to apply
local function replace(buf, lines, highlights)
  vim.bo[buf].modifiable = true
  local ok = pcall(api.nvim_buf_set_lines, buf, 0, -1, false, lines)
  if ok then
    vim.bo[buf].modifiable = false
    if highlights then
      ui.add_highlights(M.buf, highlights)
    end
  end
end

---@return boolean, table|nil, table|nil, table|nil
local function get_outline_content()
  local buf = api.nvim_get_current_buf()
  local outline = M.outlines[vim.uri_from_bufnr(buf)]
  if not outline or vim.tbl_isempty(outline) then
    return false
  end
  local lines, highlights = get_display_props(outline)
  return true, lines, highlights, outline
end

function _G.__flutter_tools_refresh_outline()
  if not utils.buf_valid(M.buf) then
    return
  end
  local ok, lines, highlights = get_outline_content()
  if ok then
    replace(M.buf, lines, highlights)
  end
end

function _G.__flutter_tools_select_outline_item()
  local line = fn.line(".")
  local uri = vim.b.outline_uri
  if not uri then
    return utils.echomsg([[Sorry! this item can't be opened]])
  end
  local outline = M.outlines[uri]
  local item = outline[line]
  if not item then
    return utils.echomsg([[Sorry! this item can't be opened]])
  end
  vim.cmd("drop " .. vim.uri_to_fname(uri))
  -- For whatever reason the cursor always lands one row up and two columns
  -- behind so handle that
  fn.cursor(item.start_line + 1, item.start_col + 2)
end

local function highlight_current_item(item)
  if not utils.buf_valid(M.buf) then
    return
  end
  ui.clear_highlights(M.buf, outline_ns_id)
  ui.add_highlights(M.buf, {
    {
      highlight = hl_prefix .. "SelectedOutlineItem",
      line_number = item.lnum,
      column_start = item.buf_start,
      column_end = item.buf_end + 1, -- add one for padding
    },
  }, outline_ns_id)
end

local function is_outline_open()
  local is_open = false
  local wins = api.nvim_tabpage_list_wins(0)
  for _, win in ipairs(wins) do
    if M.buf == api.nvim_win_get_buf(win) then
      is_open = true
      break
    end
  end
  return is_open
end

function _G.__flutter_tools_set_current_item()
  local curbuf = api.nvim_get_current_buf()
  if not utils.buf_valid(M.buf) or not is_outline_open() or curbuf == M.buf then
    return
  end
  local uri = vim.uri_from_bufnr(curbuf)
  local outline = M.outlines[uri]
  if vim.tbl_isempty(outline) then
    return
  end
  local cursor = api.nvim_win_get_cursor(0)
  local lnum = cursor[1] - 1
  local column = cursor[2] - 1
  local current_item
  if not lnum or not column then
    return
  end
  for _, item in ipairs(outline) do
    if
      item
      and not vim.tbl_isempty(item)
      and (lnum > item.start_line or (lnum == item.start_line and column >= item.start_col))
      and (lnum < item.end_line or (lnum == item.end_line and column < item.end_col))
    then
      current_item = item
    end
  end
  if current_item then
    local item_buf = vim.uri_to_bufnr(outline.uri)
    if item_buf ~= curbuf then
      return
    end
    highlight_current_item(current_item)
    local win = fn.bufwinid(M.buf)
    -- nvim_win_set_cursor is a 1,0 based method i.e.
    -- the row should be one based and the column 0 based
    api.nvim_win_set_cursor(win, { current_item.lnum + 1, current_item.buf_start })
  end
end

function M.open()
  local cfg = config.get()
  local options = cfg.outline
  local ok, lines, highlights, outline = get_outline_content()
  if not ok then
    return utils.echomsg([[Sorry! There is no outline for this file]])
  end
  local buf_loaded = utils.buf_valid(M.buf)
  if not buf_loaded and not vim.tbl_isempty(lines) then
    ui.open_split({
      open_cmd = options.open_cmd,
      filetype = outline_filetype,
      filename = outline_filename,
    }, setup_outline_window(
      lines,
      highlights
    ))
  else
    replace(M.buf, lines, highlights)
  end
  vim.b.outline_uri = outline.uri
end

function M.document_outline(_, _, data, _)
  local outline = data.outline or {}
  local result = {}
  if not outline.children or #outline.children == 0 then
    return
  end
  for _, item in ipairs(outline.children) do
    parse_outline(result, item)
  end
  result.uri = data.uri
  M.outlines[data.uri] = result
  vim.cmd([[doautocmd User FlutterOutlineChanged]])
end

return M
