-- lua rewrite of the resolve_url function in the Dart plugin
-- https://github.com/dart-lang/dart-vim-plugin/blob/4bdc04e2540edf90fda2812434c11d19dc04bc8f/autoload/dart.vim#L94
local M = {}

local function resolve(path)
  -- Use vim.loop.fs_realpath to resolve symbolic links and get the absolute path
  local real_path = vim.loop.fs_realpath(path)
  -- If the path cannot be resolved, return the original
  return real_path or path
end

-- Finds a file named `path` in any directory above the open file
-- Returns a boolean (found or not) and the file path
local function find_file(path)
  -- Get the directory path of the current buffer
  local dir_path = vim.fn.expand("%:p:h")

  -- Search upwards through parent directories
  while true do
    local file_path = vim.fs.joinpath(dir_path, path)

    -- If the file is found, return true and the path
    if vim.fn.filereadable(file_path) == 1 then return true, file_path end

    -- Move to the parent directory
    local parent = vim.fn.fnamemodify(dir_path, ":h")

    -- If we reach the root directory, break out of the loop
    if dir_path == parent then break end

    -- Continue searching in the parent directory
    dir_path = parent
  end

  -- Return false and an empty string if not found
  return false, ""
end

-- A map from package name to lib directory parsed from a 'package_config.json'.
-- Returns a boolean indicating whether it was found, and the package map.
local function get_package_map()
  -- Try to find 'package_config.json' first
  local found, package_config = find_file(vim.fs.joinpath(".dart_tool", "package_config.json"))

  if found then
    local dart_tool_dir = vim.fn.fnamemodify(package_config, ":p:h")
    local content = table.concat(vim.fn.readfile(package_config), "\n")
    local packages_dict = vim.fn.json_decode(content)

    if packages_dict["configVersion"] ~= 2 then
      error("Unsupported version of package_config.json")
      return false, {}
    end

    local map = {}
    for _, package in ipairs(packages_dict["packages"]) do
      local name = package["name"]
      local uri = package["rootUri"]
      local package_uri = package["packageUri"] or ""
      local lib_dir = ""

      -- Resolve file path from uri and packageUri
      if uri:match("file:/") then
        uri = uri:gsub("file://", "")
        lib_dir = resolve(vim.fs.joinpath(uri, package_uri):gsub("/$", ""))
      else
        lib_dir = resolve(vim.fs.joinpath(dart_tool_dir, uri, package_uri):gsub("/$", ""))
      end

      map[name] = lib_dir
    end

    return true, map
  end

  -- Return false and an empty map if nothing is found
  return false, {}
end

-- Finds the path to `uri`.
--
-- Looks for a package_config.json file to resolve the path.
-- If the path cannot be resolved, or is not a package: uri, returns the original.
function M.resolve_url(uri)
  -- Extract package name
  local package_name = uri:match("([%w_]+)/.*")
  if not package_name then return uri end

  -- Fetch package map
  local found, package_map = get_package_map()
  if not found then
    error("Cannot find package_config.json file")
    return uri
  end

  -- Check if package name is in the package map
  if not package_map[package_name] then
    error("No package mapping for " .. package_name)
    return uri
  end

  -- Get the path to the package's lib folder
  local package_lib = package_map[package_name]

  -- Replace the package name part of the URI with the actual package path
  local resolved_uri = uri:gsub("^" .. package_name, package_lib)

  return resolved_uri
end

return M
