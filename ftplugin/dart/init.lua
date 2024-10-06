require("flutter-tools.lsp").attach()

vim.opt_local.comments = [[sO:*\ -,mO:*\ \ ,exO:*/,s1:/*,mb:*,ex:*/,:///,://]]
vim.opt_local.commentstring = [[//%s]]
vim.opt.includeexpr = "v:lua.require('flutter-tools.resolve_url').resolve_url(v:fname)"

local function is_nonmodifiable_path()
  local path_parts = { [[.pub-cache]], [[Pub\Cache]], [[/fvm/versions/]] }
  local full_path = vim.fn.expand("%:p")
  if full_path then
    for _, path_part in ipairs(path_parts) do
      if full_path:find(path_part, nil, true) then return true end
    end
  end
  return false
end
-- Prevent writes to files in the pub cache and FVM folder.
if is_nonmodifiable_path() then vim.opt_local.modifiable = false end
