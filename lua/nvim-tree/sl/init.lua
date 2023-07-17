local log = require "nvim-tree.log"
local utils = require "nvim-tree.utils"
local sl_utils = require "nvim-tree.sl.utils"
local Runner = require "nvim-tree.sl.runner"
local Watcher = require("nvim-tree.watcher").Watcher
local Iterator = require "nvim-tree.iterators.node-iterator"
local explorer_node = require "nvim-tree.explorer.node"

local M = {
  config = {},
  projects = {},
  cwd_to_project_root = {},
}

-- Files under .sl that should result in a reload when changed.
-- Utilities (like watchman) can also write to this directory (often) and aren't useful for us.
local WATCHED_FILES = {
  "config",
  "undolog",
}

local function reload_scm_status(project_root, path, project, scm_status)
  if path then
    for p in pairs(project.files) do
      if p:find(path, 1, true) == 1 then
        project.files[p] = nil
      end
    end
    project.files = vim.tbl_deep_extend("force", project.files, scm_status)
  else
    project.files = scm_status
  end

  project.dirs = sl_utils.file_status_to_dir_status(project.files, project_root)
end

function M.name()
  return "sl"
end

function M.reload()
  log.line("sl", "reload")
  if not M.config.sl.enable then
    return {}
  end

  for project_root in pairs(M.projects) do
    M.reload_project(project_root)
  end

  return M.projects
end

function M.reload_project(project_root, path, callback)
  log.line("sl", "reload_project")
  local project = M.projects[project_root]
  if not project or not M.config.sl.enable then
    if callback then
      callback()
    end
    return
  end

  if path and path:find(project_root, 1, true) ~= 1 then
    if callback then
      callback()
    end
    return
  end

  local opts = {
    project_root = project_root,
    path = path,
    list_ignored = true,
    timeout = M.config.sl.timeout,
  }

  if callback then
    Runner.run(opts, function(scm_status)
      reload_scm_status(project_root, path, project, scm_status)
      callback()
    end)
  else
    -- TODO use callback once async/await is available
    local scm_status = Runner.run(opts)
    reload_scm_status(project_root, path, project, scm_status)
  end
end

function M.get_project(project_root)
  log.line("sl", "get_project")
  return M.projects[project_root]
end

function M.get_project_root(cwd)
  log.line("sl", "get_project_root")
  if not M.config.sl.enable then
    return nil
  end

  if M.cwd_to_project_root[cwd] then
    return M.cwd_to_project_root[cwd]
  end

  if M.cwd_to_project_root[cwd] == false then
    return nil
  end

  local stat, _ = vim.loop.fs_stat(cwd)
  if not stat or stat.type ~= "directory" then
    return nil
  end

  local toplevel = sl_utils.get_toplevel(cwd)
  for _, disabled_for_dir in ipairs(M.config.sl.disable_for_dirs) do
    local toplevel_norm = vim.fn.fnamemodify(toplevel, ":p")
    local disabled_norm = vim.fn.fnamemodify(disabled_for_dir, ":p")
    if toplevel_norm == disabled_norm then
      return nil
    end
  end

  M.cwd_to_project_root[cwd] = toplevel
  return M.cwd_to_project_root[cwd]
end

local function reload_tree_at(project_root)
  if not M.config.sl.enable then
    return nil
  end

  log.line("watcher", "sl event executing '%s'", project_root)
  local root_node = utils.get_node_from_path(project_root)
  if not root_node then
    return
  end

  M.reload_project(project_root, nil, function()
    local scm_status = M.get_project(project_root)

    Iterator.builder(root_node.nodes)
      :hidden()
      :applier(function(node)
        local parent_ignored = explorer_node.is_scm_ignored(node.parent)
        explorer_node.update_scm_status(node, parent_ignored, scm_status)
      end)
      :recursor(function(node)
        return node.nodes and #node.nodes > 0 and node.nodes
      end)
      :iterate()

    require("nvim-tree.renderer").draw()
  end)
end

function M.load_project_status(cwd)
  log.line("sl", "get_project_status")
  if not M.config.sl.enable then
    return {}
  end

  local project_root = M.get_project_root(cwd)
  if not project_root then
    M.cwd_to_project_root[cwd] = false
    return {}
  end

  local status = M.projects[project_root]
  if status then
    return status
  end

  local scm_status = Runner.run {
    project_root = project_root,
    list_ignored = true,
    timeout = M.config.sl.timeout,
  }

  local watcher = nil
  if M.config.filesystem_watchers.enable then
    log.line("watcher", "sl start")

    local callback = function(w)
      log.line("watcher", "sl event scheduled '%s'", w.project_root)
      utils.debounce("sl:watcher:" .. w.project_root, M.config.filesystem_watchers.debounce_delay, function()
        if w.destroyed then
          return
        end
        reload_tree_at(w.project_root)
      end)
    end

    watcher = Watcher:new(utils.path_join { project_root, ".sl" }, WATCHED_FILES, callback, {
      project_root = project_root,
    })
  end

  M.projects[project_root] = {
    files = scm_status,
    dirs = sl_utils.file_status_to_dir_status(scm_status, project_root),
    watcher = watcher,
  }
  return M.projects[project_root]
end

function M.purge_state()
  log.line("sl", "purge_state")
  M.projects = {}
  M.cwd_to_project_root = {}
end

--- Disable sapling (sl) integration permanently
function M.disable_sl_integration()
  log.line("sl", "disabling sl integration")
  M.purge_state()
  M.config.sl.enable = false
end

function M.setup(opts)
  log.line("sl", "setup")
  M.config.sl = opts.sl
  M.config.filesystem_watchers = opts.filesystem_watchers
end

return M
