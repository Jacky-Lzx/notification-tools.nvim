local M = {}
local uv = vim.uv or vim.loop
local next_id = 0

function M.now()
  return uv.hrtime() / 1e6
end

function M.new(config)
  return {
    config = config,
    notices = {},
    tasks = {},
    history = {},
    serial = 0,
    dnd = config.notification.dnd,
  }
end

function M.id()
  next_id = next_id + 1
  return "notification-tools:" .. next_id
end

function M.archive(state, notice)
  for i, item in ipairs(state.history) do
    if item.id == notice.id then
      table.remove(state.history, i)
      break
    end
  end
  state.history[#state.history + 1] = vim.deepcopy(notice)
  while #state.history > state.config.history_size do
    table.remove(state.history, 1)
  end
end

function M.sorted(items, oldest_first)
  local result = vim.tbl_values(items)
  table.sort(result, function(a, b)
    if oldest_first then
      return a.order < b.order
    end
    return a.order > b.order
  end)
  return result
end

-- Fade within the existing lifetime; expiration and API snapshots are unchanged.
function M.opacity(item, duration, now)
  if not item or not item.expires or duration == 0 then
    return 1
  end
  duration = math.min(duration, item.timeout or item.lifetime or duration)
  if duration <= 0 then
    return 1
  end
  return math.max(0, math.min(1, (item.expires - (now or M.now())) / duration))
end

function M.expire(state)
  local now = M.now()
  for id, notice in pairs(state.notices) do
    if notice.expires and now >= notice.expires then
      state.notices[id] = nil
    end
  end
  for id, task in pairs(state.tasks) do
    if task.expires and now >= task.expires then
      state.tasks[id] = nil
    elseif not task.done and state.config.progress.stale_timeout > 0 then
      if now - task.updated >= state.config.progress.stale_timeout then
        task.done = true
        task.finished = now
        task.status = "error"
        task.message = "Timed out"
        task.expires = now + state.config.progress.done_ttl
        task.lifetime = state.config.progress.done_ttl
      end
    end
  end
end

return M
