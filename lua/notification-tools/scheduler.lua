local M = {}
local uv = vim.uv or vim.loop
local function now()
  return uv.hrtime() / 1e6
end

-- One cancellable, one-shot timer per instance. Callback returns its next delay.
function M.new(callback, interval)
  local self = { closed = false }
  local timer, queued, running, dirty, last = nil, false, false, false, -math.huge
  local function disarm()
    if timer then
      timer:stop()
      timer:close()
      timer = nil
    end
  end
  local enqueue, arm
  local function run()
    queued = false
    if self.closed then
      return
    end
    disarm()
    running, dirty, last = true, false, now()
    local ok, delay = xpcall(callback, debug.traceback)
    running = false
    if not ok then
      error(delay)
    end
    if self.closed then
      return
    end
    if dirty then
      self:request()
    elseif delay then
      arm(delay)
    end
  end
  enqueue = function()
    if queued or self.closed then
      return
    end
    queued = true
    disarm()
    vim.schedule(run)
  end
  arm = function(delay)
    if self.closed then
      return
    end
    if not timer then
      timer = assert(uv.new_timer())
    end
    timer:start(math.max(1, math.ceil(delay)), 0, enqueue)
  end
  function self:request()
    if self.closed then
      return
    end
    dirty = true
    if queued or running then
      return
    end
    local remaining = interval - (now() - last)
    if remaining <= 0 then
      enqueue()
    else
      arm(remaining)
    end
  end
  function self:close()
    self.closed = true
    disarm()
  end
  return self
end

return M
