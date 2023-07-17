local M = {}

-- node.scm_status structure:
-- {
--   file = string | nil,
--   dir = {
--     direct = { string } | nil,
--     indirect = { string } | nil,
--   } | nil,
-- }

local function get_dir_scm_status(parent_ignored, status, absolute_path)
  if parent_ignored then
    return { file = "!!" }
  end

  return {
    file = status.files and status.files[absolute_path],
    dir = status.dirs and {
      direct = status.dirs.direct[absolute_path],
      indirect = status.dirs.indirect[absolute_path],
    },
  }
end

local function get_scm_status(parent_ignored, status, absolute_path)
  local file_status = parent_ignored and "!!" or status.files and status.files[absolute_path]
  return { file = file_status }
end

function M.has_one_child_folder(node)
  return #node.nodes == 1 and node.nodes[1].nodes and vim.loop.fs_access(node.nodes[1].absolute_path, "R")
end

function M.update_scm_status(node, parent_ignored, status)
  local get_status
  if node.nodes then
    get_status = get_dir_scm_status
  else
    get_status = get_scm_status
  end

  -- status of the node's absolute path
  node.scm_status = get_status(parent_ignored, status, node.absolute_path)

  -- status of the link target, if the link itself is not dirty
  if node.link_to and not node.scm_status then
    node.scm_status = get_status(parent_ignored, status, node.link_to)
  end
end

function M.get_scm_status(node)
  local scm_status = node and node.scm_status
  if not scm_status then
    -- status doesn't exist
    return nil
  end

  if not node.nodes then
    -- file
    return scm_status.file and { scm_status.file }
  end

  -- dir
  -- TODO: Review
  if not M.config.git.show_on_dirs then
    return nil
  end

  local status = {}
  if not require("nvim-tree.lib").get_last_group_node(node).open or M.config.git.show_on_open_dirs then
    -- dir is closed or we should show on open_dirs
    if scm_status.file ~= nil then
      table.insert(status, scm_status.file)
    end
    if scm_status.dir ~= nil then
      if scm_status.dir.direct ~= nil then
        for _, s in pairs(node.scm_status.dir.direct) do
          table.insert(status, s)
        end
      end
      if scm_status.dir.indirect ~= nil then
        for _, s in pairs(node.scm_status.dir.indirect) do
          table.insert(status, s)
        end
      end
    end
  else
    -- dir is open and we shouldn't show on open_dirs
    if scm_status.file ~= nil then
      table.insert(status, scm_status.file)
    end
    if scm_status.dir ~= nil and scm_status.dir.direct ~= nil then
      local deleted = {
        [" D"] = true,
        ["D "] = true,
        ["RD"] = true,
        ["DD"] = true,
      }
      for _, s in pairs(node.scm_status.dir.direct) do
        if deleted[s] then
          table.insert(status, s)
        end
      end
    end
  end
  if #status == 0 then
    return nil
  else
    return status
  end
end

function M.is_scm_ignored(node)
  return node.scm_status and node.scm_status.file == "!!"
end

function M.node_destroy(node)
  if not node then
    return
  end

  if node.watcher then
    node.watcher:destroy()
    node.watcher = nil
  end
end

function M.setup(opts)
  M.config = {
    -- TODO: Remove
    git = opts.git,
    scm = opts.scm,
  }
end

return M
