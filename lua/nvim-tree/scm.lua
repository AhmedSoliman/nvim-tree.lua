local log = require "nvim-tree.log"
local git = require "nvim-tree.git"
local sl = require "nvim-tree.sl"

local M = {
  config = {},
  -- TODO: I'm not sure if we will need those or not
  cwd_to_scm_module = {},
}

-- Detect SCM and return the correct module.
function M.scm_for_dir(cwd)
  -- Default is git.
  local scm_module = git

  if M.cwd_to_scm_module[cwd] then
    scm_module = M.cwd_to_scm_module[cwd]
    log.line("scm", "scm_module for cwd=%s is already known!", cwd)
  else
    -- try to detect scm module
    if git.get_project_root(cwd) then
      scm_module = git
    elseif sl.get_project_root(cwd) then
      log.line("scm", "%s a sapling project", cwd)
      scm_module = sl
    end
    M.cwd_to_scm_module[cwd] = scm_module
  end
  log.line("scm", "scm_module = %s for cwd = %s", M.cwd_to_scm_module[cwd].name(), cwd)
  return M.cwd_to_scm_module[cwd]
end

function M.reload()
  log.line("scm", "reload")
  if not M.config.scm.enable then
    return {}
  end

  local projects = {}

  -- git projects
  for k, v in pairs(git.reload()) do projects[k] = v end
  -- sl projects
  for k, v in pairs(sl.reload()) do projects[k] = v end
  return projects
end

function M.reload_project(project_root, path, callback)
  log.line("scm", "reload_project")
  return M.scm_for_dir(project_root).reload_project(project_root, path, callback)
end

function M.get_project(project_root)
  log.line("scm", "get_project")
  return M.scm_for_dir(project_root).get_project(project_root)
end

function M.get_project_root(cwd)
  log.line("scm", "get_project_root")

  return M.scm_for_dir(cwd).get_project_root(cwd)
end

function M.load_project_status(cwd)
  log.line("scm", "load_project_status")

  local st = M.scm_for_dir(cwd).load_project_status(cwd)
  log.line("scm", "load_project_status: st = %s", vim.inspect(st))
  return st
end

function M.purge_state()
  log.line("scm", "purge_state")
  M.projects = {}
  M.cwd_to_project_root = {}
  M.project_to_scm_module = {}

  git.scm_module.purge_state()
  sl.scm_module.purge_state()
end

function M.setup(opts)
  log.line("scm", "setup")
  M.config.scm = opts.scm
  git.setup(opts)
  sl.setup(opts)
end

return M
