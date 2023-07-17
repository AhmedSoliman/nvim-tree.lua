local M = {}
local log = require "nvim-tree.log"

local has_cygpath = vim.fn.executable "cygpath" == 1

--- Retrieve the git toplevel directory
--- @param cwd string path
--- @return string|nil toplevel absolute path
function M.get_toplevel(cwd)
  local profile = log.profile_start("sl toplevel %s", cwd)

  local cmd = { "sl", "--cwd", cwd, "root" }
  log.line("sl", "%s", vim.inspect(cmd))

  local toplevel = vim.fn.system(cmd)

  log.raw("sl", toplevel)
  log.profile_end(profile)

  if vim.v.shell_error ~= 0 or not toplevel or #toplevel == 0 or toplevel:match "fatal" then
    return nil
  end

  -- git always returns path with forward slashes
  if vim.fn.has "win32" == 1 then
  --   -- msys2 git support
  --   if has_cygpath then
  --     toplevel = vim.fn.system("cygpath -w " .. vim.fn.shellescape(toplevel:sub(0, -2)))
  --     if vim.v.shell_error ~= 0 then
  --       return nil
  --     end
  --   end
  --   toplevel = toplevel:gsub("/", "\\")
  end

  -- remove newline
  return toplevel:sub(0, -2)
end

local function nil_insert(t, k)
  t = t or {}
  t[k] = true
  return t
end

function M.file_status_to_dir_status(status, cwd)
  local direct = {}
  for p, s in pairs(status) do
    if s ~= "!!" then
      local modified = vim.fn.fnamemodify(p, ":h")
      direct[modified] = nil_insert(direct[modified], s)
    end
  end

  local indirect = {}
  for dirname, statuses in pairs(direct) do
    for s, _ in pairs(statuses) do
      local modified = dirname
      while modified ~= cwd and modified ~= "/" do
        modified = vim.fn.fnamemodify(modified, ":h")
        indirect[modified] = nil_insert(indirect[modified], s)
      end
    end
  end

  local r = { indirect = indirect, direct = direct }
  for _, d in pairs(r) do
    for dirname, statuses in pairs(d) do
      local new_statuses = {}
      for s, _ in pairs(statuses) do
        table.insert(new_statuses, s)
      end
      d[dirname] = new_statuses
    end
  end
  return r
end

return M
