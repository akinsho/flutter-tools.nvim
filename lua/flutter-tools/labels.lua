local api = vim.api

local M = {}

local namespace = api.nvim_create_namespace("flutter_tools_closing_labels")

local function render_labels(labels, opts)
  api.nvim_buf_clear_namespace(0, namespace, 0, -1)
  opts = opts or {}
  local highlight = opts.highlight or "Comment"

  -- Have ot use `rawget` to override what the default format is that we provide in config.
  local user_format = rawget(opts, "format")

  local prefix = opts.prefix
  if prefix and user_format then
    error(
      "[flutter-tools.labels] Cannot have both prefix and format specified" .. vim.inspect(opts)
    )
  end

  -- A bit complicated, but basically just keeps backwards compat of passing "prefix"
  -- while still allowing users to pass "format" instead.
  local format
  if user_format then
    format = user_format
  elseif prefix then
    format = prefix .. "%s"
  else
    format = opts.format
  end

  for _, item in ipairs(labels) do
    local line = item.range["end"].line
    api.nvim_buf_set_virtual_text(0, namespace, tonumber(line), {
      { string.format(format, item.label), highlight },
    }, {})
  end
end

--- returns a function which handles rendering floating labels
function M.closing_tags(err, response, _)
  local conf = require("flutter-tools.config").get()
  local opts = conf.closing_tags
  if err or not opts.enabled then
    return
  end
  local uri = response.uri
  -- This check is meant to prevent stray events from over-writing labels that
  -- don't match the current buffer.
  if uri ~= vim.uri_from_bufnr(0) then
    return
  end
  render_labels(response.labels, opts)
end

return M
