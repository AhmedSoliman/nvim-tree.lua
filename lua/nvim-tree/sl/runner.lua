local log = require "nvim-tree.log"
local utils = require "nvim-tree.utils"
local notify = require "nvim-tree.notify"

local Runner = {}
Runner.__index = Runner

local timeouts = 0
local MAX_TIMEOUTS = 5

local mapping = {
  ["M"] = "C ",
  ["R"] = "D ",
  ["I"] = "!!",
  ["A"] = "A ",
  ["?"] = " A",
}

-- FREEZE BLOCK
-- We don't show files in target/ anymore, but the directory itself is:
--   - Watched by watcher (the original big issue)

function Runner:_parse_status_output(status, path)
  -- replacing slashes if on windows
  if vim.fn.has "win32" == 1 then
    path = path:gsub("/", "\\")
  end
  if #status > 0 and #path > 0 then
    -- IDEA: rewrite Status match git?
    --local git_status = mapping[status]
    status = mapping[status]
    log.line("sl", "status: '%s', path: '%s'", status, path)
    self.output[utils.path_remove_trailing(utils.path_join { self.project_root, path })] = status
  end
end

function Runner:_handle_incoming_data(prev_output, incoming)
  if incoming and utils.str_find(incoming, "\n") then
    local prev = prev_output .. incoming
    local i = 1
    local skip_next_line = false
    for line in prev:gmatch "[^\n]*\n" do
      if skip_next_line then
        skip_next_line = false
      else
        local status = line:sub(1, 1)
        local path = line:sub(3, -2)
        if utils.str_find(status, "R") then
          -- skip next line if it is a rename entry
          skip_next_line = true
        end
        self:_parse_status_output(status, path)
      end
      i = i + #line
    end

    return prev:sub(i, -1)
  end

  if incoming then
    return prev_output .. incoming
  end

  for line in prev_output:gmatch "[^\n]*\n" do
    self._parse_status_output(line)
  end

  return ""
end

function Runner:_getopts(stdout_handle, stderr_handle)
  local ignored = self.list_ignored and "--ignored" or ""
  return {
    args = { "status", "--color=never", "-mardu0", "--terse=i", ignored, self.path },
    cwd = self.project_root,
    stdio = { nil, stdout_handle, stderr_handle },
  }
end

function Runner:_log_raw_output(output)
  if log.enabled "sl" and output and type(output) == "string" then
    log.raw("sl", "%s", output)
    log.line("sl", "done")
  end
end

function Runner:_run_sl_job(callback)
  local handle, pid
  local stdout = vim.loop.new_pipe(false)
  local stderr = vim.loop.new_pipe(false)
  local timer = vim.loop.new_timer()

  local function on_finish(rc)
    self.rc = rc or 0
    if timer:is_closing() or stdout:is_closing() or stderr:is_closing() or (handle and handle:is_closing()) then
      if callback then
        callback()
      end
      return
    end
    timer:stop()
    timer:close()
    stdout:read_stop()
    stderr:read_stop()
    stdout:close()
    stderr:close()
    if handle then
      handle:close()
    end

    pcall(vim.loop.kill, pid)

    if callback then
      callback()
    end
  end

  local opts = self:_getopts(stdout, stderr)
  log.line("sl", "running job with timeout %dms", self.timeout)
  log.line("sl", "sl %s", table.concat(utils.array_remove_nils(opts.args), " "))

  handle, pid = vim.loop.spawn(
    "sl",
    opts,
    vim.schedule_wrap(function(rc)
      on_finish(rc)
    end)
  )

  timer:start(
    self.timeout,
    0,
    vim.schedule_wrap(function()
      on_finish(-1)
    end)
  )

  local output_leftover = ""
  local function manage_stdout(err, data)
    if err then
      return
    end
    if data then
      data = data:gsub("%z", "\n")
    end
    self:_log_raw_output(data)
    output_leftover = self:_handle_incoming_data(output_leftover, data)
  end

  local function manage_stderr(_, data)
    self:_log_raw_output(data)
  end

  vim.loop.read_start(stdout, vim.schedule_wrap(manage_stdout))
  vim.loop.read_start(stderr, vim.schedule_wrap(manage_stderr))
end

function Runner:_wait()
  local function is_done()
    return self.rc ~= nil
  end

  while not vim.wait(30, is_done) do
  end
end

function Runner:_finalise(opts)
  if self.rc == -1 then
    log.line("sl", "job timed out  %s %s", opts.project_root, opts.path)
    timeouts = timeouts + 1
    if timeouts == MAX_TIMEOUTS then
      notify.warn(
        string.format(
          "%d sl jobs have timed out after %dms, disabling sl integration. Try increasing scm.timeout",
          timeouts,
          opts.timeout
        )
      )
      require("nvim-tree.sl").disable_sl_integration()
    end
  elseif self.rc ~= 0 then
    log.line("sl", "job fail rc %d %s %s", self.rc, opts.project_root, opts.path)
  else
    log.line("sl", "job success    %s %s", opts.project_root, opts.path)
  end
end

--- Runs a sl process, which will be killed if it takes more than timeout which defaults to 400ms
--- @param opts table
--- @param callback function|nil executed passing return when complete
--- @return table|nil status by absolute path, nil if callback present
function Runner.run(opts, callback)
  local self = setmetatable({
    project_root = opts.project_root,
    path = opts.path,
    list_ignored = opts.list_ignored,
    --timeout = opts.timeout or 400,
    timeout = 4000,
    output = {},
    rc = nil, -- -1 indicates timeout
  }, Runner)

  local async = callback ~= nil
  local profile = log.profile_start("sl %s job %s %s", async and "async" or "sync", opts.project_root, opts.path)

  if async and callback then
    -- async, always call back
    self:_run_sl_job(function()
      log.profile_end(profile)

      self:_finalise(opts)

      callback(self.output)
    end)
  else
    -- sync, maybe call back
    self:_run_sl_job()
    self:_wait()

    log.profile_end(profile)

    self:_finalise(opts)

    if callback then
      callback(self.output)
    else
      return self.output
    end
  end
end

return Runner
