local lazy = require("flutter-tools.lazy")
local utils = lazy.require("flutter-tools.utils") ---@module "flutter-tools.utils"
local path = lazy.require("flutter-tools.utils.path") ---@module "flutter-tools.utils.path"
local ui = lazy.require("flutter-tools.ui") ---@module "flutter-tools.ui"
local config = lazy.require("flutter-tools.config") ---@module "flutter-tools.config"
local Job = require("plenary.job")

---@class flutter.Paths
---
--- The path to the Flutter CLI.
---@field flutter_bin string
---
--- The path to the root directory of the Flutter SDK.
---@field flutter_sdk string
---
--- The path to the Dart CLI.
---@field dart_bin string
---
--- The path to the root directory of the Dart SDK used by the Flutter SDK.
---@field dart_sdk string
---
--- True if fvm provides the Flutter SDK, otherwise nil or false.
---@field fvm boolean?

---@private
---@class flutter.internal.Paths
---@field flutter_bin string
---@field flutter_sdk string
---@field dart_bin string

local fn = vim.fn
local fs = vim.fs
local uv = vim.uv

local M = {}

local dart_sdk = path.join("cache", "dart-sdk")

---@type flutter.Paths?
local cached_paths = nil

local function flutter_sdk_root(bin_path)
  -- convert path/to/flutter/bin/flutter into path/to/flutter
  return fn.fnamemodify(bin_path, ":h:h")
end

local function dart_sdk_root(paths)
  if paths.flutter_sdk then
    -- On Linux installations with snap the dart SDK can be further nested inside a bin directory
    -- so it's /bin/cache/dart-sdk whereas else where it is /cache/dart-sdk
    local segments = { paths.flutter_sdk, "cache" }
    if not path.is_dir(path.join(unpack(segments))) then table.insert(segments, 2, "bin") end
    if path.is_dir(path.join(unpack(segments))) then
      -- remove the /cache/ directory as it's already part of the SDK path above
      segments[#segments] = nil
      return path.join(unpack(utils.flatten({ segments, dart_sdk })))
    end
  end

  if utils.executable("flutter") then
    local flutter_path = fn.resolve(fn.exepath("flutter"))
    local flutter_bin = fn.fnamemodify(flutter_path, ":h")
    return path.join(flutter_bin, dart_sdk)
  end

  if utils.executable("dart") then return fn.resolve(fn.exepath("dart")) end

  return ""
end

local function flutter_sdk_dart_bin(flutter_sdk)
  -- retrieve the Dart binary from the Flutter SDK
  local binary_name = path.is_windows and "dart.bat" or "dart"
  local dart_search_paths = {
    path.join(flutter_sdk, "bin", binary_name),
    path.join(flutter_sdk, "bin", "cache", "dart-sdk", "bin", binary_name)
  }

  for _, _path in ipairs(dart_search_paths) do
    if path.exists(_path) then
      return _path
    end
  end

  return ""
end

--- Get paths for flutter and dart based on the binary locations.
---@return flutter.internal.Paths?
local function get_default_binaries()
  local flutter_bin = fn.resolve(fn.exepath("flutter"))
  if #flutter_bin <= 0 then return nil end
  return {
    flutter_bin = flutter_bin,
    dart_bin = fn.resolve(fn.exepath("dart")),
    flutter_sdk = flutter_sdk_root(flutter_bin),
  }
end

--- Execute user's lookup command and pass it to the job callback.
---@param lookup_cmd string
---@param callback fun(paths:flutter.internal.Paths):nil
local function path_from_lookup_cmd(lookup_cmd, callback)
  local paths = {}
  local parts = vim.split(lookup_cmd, " ")
  local cmd = parts[1]
  local args = vim.list_slice(parts, 2, #parts)

  local job = Job:new({ command = cmd, args = args })

  job:after_failure(
    vim.schedule_wrap(
      function()
        ui.notify(string.format("Error running %s", lookup_cmd), ui.ERROR, { timeout = 5000 })
      end
    )
  )

  job:after_success(vim.schedule_wrap(function(j, _)
    local result = j:result()
    local flutter_sdk_path = result[1]
    if flutter_sdk_path then
      paths.dart_bin = flutter_sdk_dart_bin(flutter_sdk_path)
      paths.flutter_bin = path.join(flutter_sdk_path, "bin", "flutter")
      paths.flutter_sdk = flutter_sdk_path
      callback(paths)
    else
      paths = get_default_binaries()
      callback(paths)
    end
  end))

  job:start()
end

local function flutter_bin_from_fvm()
  local fvm_root =
    fs.dirname(fs.find(".fvm", { path = uv.cwd(), upward = true, type = "directory" })[1])

  local binary_name = path.is_windows and "flutter.bat" or "flutter"
  local flutter_bin_symlink = path.join(fvm_root, ".fvm", "flutter_sdk", "bin", binary_name)
  flutter_bin_symlink = fn.exepath(flutter_bin_symlink)

  local flutter_bin = uv.fs_realpath(flutter_bin_symlink)
  if path.exists(flutter_bin_symlink) and path.exists(flutter_bin) then return flutter_bin end
end

--- Reset the internally cached SDK paths.
function M.reset_paths() cached_paths = nil end

--- Fetch the paths to the users binaries.
---@param callback fun(paths: flutter.Paths):nil
function M.get(callback)
  if cached_paths then return callback(cached_paths) end
  if config.fvm then
    local flutter_bin = flutter_bin_from_fvm()
    if flutter_bin then
      cached_paths = {
        flutter_bin = flutter_bin,
        flutter_sdk = flutter_sdk_root(flutter_bin),
        fvm = true,
        -- Provide default values to make the linter happy.
        dart_sdk = "",
        dart_bin = "",
      }
      cached_paths.dart_sdk = dart_sdk_root(cached_paths)
      cached_paths.dart_bin = flutter_sdk_dart_bin(cached_paths.flutter_sdk)
      return callback(cached_paths)
    end
  end

  if config.flutter_path then
    local flutter_path = fn.resolve(config.flutter_path)
    cached_paths = {
      flutter_bin = flutter_path,
      flutter_sdk = flutter_sdk_root(flutter_path),
      -- Provide default values to make the linter happy.
      dart_sdk = "",
      dart_bin = "",
    }
    cached_paths.dart_sdk = dart_sdk_root(cached_paths)
    cached_paths.dart_bin = flutter_sdk_dart_bin(cached_paths.flutter_sdk)
    return callback(cached_paths)
  end

  if config.flutter_lookup_cmd then
    return path_from_lookup_cmd(config.flutter_lookup_cmd, function(paths)
      cached_paths = {
        flutter_bin = paths.flutter_bin,
        flutter_sdk = paths.flutter_sdk,
        dart_bin = paths.dart_bin,
        dart_sdk = dart_sdk_root(paths),
      }
      callback(cached_paths)
    end)
  end

  if not cached_paths then
    local internal_paths = get_default_binaries()
    if internal_paths then
      cached_paths = {
        flutter_bin = internal_paths.flutter_bin,
        flutter_sdk = internal_paths.flutter_sdk,
        dart_bin = internal_paths.dart_bin,
        dart_sdk = dart_sdk_root(internal_paths),
      }
      if cached_paths.flutter_sdk then
        cached_paths.dart_bin = flutter_sdk_dart_bin(cached_paths.flutter_sdk)
      end
    end
  end

  return callback(cached_paths)
end

--- Fetch the path to the users flutter installation.
---@param callback fun(flutter_bin: string):nil
function M.flutter(callback)
  M.get(function(paths) callback(paths.flutter_bin) end)
end

--- Fetch the path to the users dart installation.
---@param callback fun(dart_bin: string):nil
function M.dart(callback)
  M.get(function(paths) callback(paths.dart_bin) end)
end

return M
