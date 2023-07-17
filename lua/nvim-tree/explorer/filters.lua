local utils = require "nvim-tree.utils"

local M = {
  ignore_list = {},
  exclude_list = {},
}

local function is_excluded(path)
  for _, node in ipairs(M.exclude_list) do
    if path:match(node) then
      return true
    end
  end
  return false
end

---Check if the given path is scm clean/ignored
---@param path string Absolute path
---@param scm_status table from prepare
---@return boolean
local function scm(path, scm_status)
  if type(scm_status) ~= "table" or type(scm_status.files) ~= "table" or type(scm_status.dirs) ~= "table" then
    return false
  end

  -- default status to clean
  local status = scm_status.files[path]
  status = status or scm_status.dirs.direct[path] and scm_status.dirs.direct[path][1]
  status = status or scm_status.dirs.indirect[path] and scm_status.dirs.indirect[path][1]

  -- filter ignored; overrides clean as they are effectively dirty
  if M.config.filter_scm_ignored and status == "!!" then
    return true
  end

  -- filter clean
  if M.config.filter_git_clean and not status then
    return true
  end

  return false
end

---Check if the given path has no listed buffer
---@param path string Absolute path
---@param bufinfo table vim.fn.getbufinfo { buflisted = 1 }
---@param unloaded_bufnr number optional bufnr recently unloaded via BufUnload event
---@return boolean
local function buf(path, bufinfo, unloaded_bufnr)
  if not M.config.filter_no_buffer or type(bufinfo) ~= "table" then
    return false
  end

  -- filter files with no open buffer and directories containing no open buffers
  for _, b in ipairs(bufinfo) do
    if b.name == path or b.name:find(path .. "/", 1, true) and b.bufnr ~= unloaded_bufnr then
      return false
    end
  end

  return true
end

local function dotfile(path)
  return M.config.filter_dotfiles and utils.path_basename(path):sub(1, 1) == "."
end

local function custom(path)
  if not M.config.filter_custom then
    return false
  end

  local basename = utils.path_basename(path)

  -- filter custom regexes
  local relpath = utils.path_relative(path, vim.loop.cwd())
  for pat, _ in pairs(M.ignore_list) do
    if vim.fn.match(relpath, pat) ~= -1 or vim.fn.match(basename, pat) ~= -1 then
      return true
    end
  end

  local idx = path:match ".+()%.[^.]+$"
  if idx then
    if M.ignore_list["*" .. string.sub(path, idx)] == true then
      return true
    end
  end

  return false
end

---Prepare arguments for should_filter. This is done prior to should_filter for efficiency reasons.
---@param scm_status table|nil optional results of scm.load_project_status(...)
---@param unloaded_bufnr number|nil optional bufnr recently unloaded via BufUnload event
---@return table
--- scm_status: reference
--- unloaded_bufnr: copy
--- bufinfo: empty unless no_buffer set: vim.fn.getbufinfo { buflisted = 1 }
function M.prepare(scm_status, unloaded_bufnr)
  local status = {
    scm_status = scm_status or {},
    unloaded_bufnr = unloaded_bufnr,
    bufinfo = {},
  }

  if M.config.filter_no_buffer then
    status.bufinfo = vim.fn.getbufinfo { buflisted = 1 }
  end

  return status
end

-- TODO: Remove
local log = require "nvim-tree.log"

---Check if the given path should be filtered.
---@param path string Absolute path
---@param status table from prepare
---@return boolean
function M.should_filter(path, status)
  -- exclusions override all filters
  if is_excluded(path) then
    return false
  end

  local should_be_filtered = scm(path, status.scm_status)
      or buf(path, status.bufinfo, status.unloaded_bufnr)
      or dotfile(path)
      or custom(path)
  log.line("filters", "Path '%s' filtered? = %s", path, should_be_filtered)
  return should_be_filtered
end

function M.setup(opts)
  M.config = {
    filter_custom = true,
    filter_dotfiles = opts.filters.dotfiles,
    filter_scm_ignored = opts.scm.ignore,
    filter_git_clean = opts.filters.git_clean,
    filter_no_buffer = opts.filters.no_buffer,
  }

  M.ignore_list = {}
  M.exclude_list = opts.filters.exclude

  local custom_filter = opts.filters.custom
  if custom_filter and #custom_filter > 0 then
    for _, filter_name in pairs(custom_filter) do
      M.ignore_list[filter_name] = true
    end
  end
end

return M
