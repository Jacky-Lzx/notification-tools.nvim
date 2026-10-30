local M = {}
local uv = vim.uv or vim.loop
local config = require("notification-tools.config")
local records = require("notification-tools.records")
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

function M.text(value)
  return type(value) == "table" and vim.inspect(value) or tostring(value or "")
end

function M.valid_id(id)
  assert(type(id) == "string" or type(id) == "number", "id must be a string or number")
  assert(type(id) ~= "number" or (id == id and math.abs(id) < math.huge), "id must be finite")
  return id
end

function M.trim(state, items)
  if vim.tbl_count(items) <= state.config.max_pending then
    return
  end
  local sorted = M.sorted(items)
  for i = state.config.max_pending + 1, #sorted do
    items[sorted[i].id] = nil
  end
end

function M.notify(state, message, level, opts)
  opts = opts or {}
  local explicit = opts.id ~= nil or opts.replace ~= nil
  local id = opts.id or opts.replace
  if type(id) == "table" then
    id = id.id
  end
  if id ~= nil then
    M.valid_id(id)
  end
  local old = id ~= nil and state.notices[id] or nil
  level = config.level(level or (old and old.level) or vim.log.levels.INFO)
  if level < state.config.level or level == vim.log.levels.OFF then
    return nil
  end
  local timeout = opts.timeout
  if timeout == nil then
    timeout = state.config.timeout
  end
  assert(
    type(timeout) == "number" and timeout >= 0 and timeout < math.huge,
    "timeout must be finite and >= 0"
  )
  local message_text = M.text(message)
  local title = M.text(opts.title or (old and old.title) or "Notification")
  local source = M.text(opts.source or (old and old.source) or title)
  local details = opts.details ~= nil and M.text(opts.details) or (old and old.details) or ""
  local icon = opts.icon or (old and old.icon)
  local markdown = opts.markdown
  if markdown == nil and old then
    markdown = old.markdown
  end
  if markdown == nil then
    markdown = state.config.notification.markdown
  end
  assert(type(markdown) == "boolean", "markdown must be a boolean")
  local route, filter_error = "show", nil
  if state.config.notification.filter then
    local ok, result = pcall(state.config.notification.filter, {
      id = id,
      message = message_text,
      level = level,
      title = title,
      source = source,
      details = details,
      icon = icon,
      markdown = markdown,
      timeout = timeout,
    })
    if ok and (result == nil or vim.tbl_contains({ "show", "history", "drop" }, result)) then
      route = result or "show"
    else
      filter_error = ok and "expected show, history, drop or nil" or tostring(result)
    end
  end
  if route == "drop" then
    return nil
  end
  local display = route == "show"
    and (not state.dnd or level >= state.config.notification.dnd_level)
  local now = M.now()
  if not explicit and state.config.notification.merge_duplicates then
    for _, item in ipairs(M.sorted(state.notices)) do
      if
        (not item.expires or item.expires > now)
        and item.message == message_text
        and item.title == title
        and item.source == source
        and item.display == display
        and item.details == details
        and item.level == level
        and item.icon == icon
        and item.timeout == timeout
        and item.markdown == markdown
      then
        old, id = item, item.id
        break
      end
    end
  end
  id = id or M.id()
  local same = old
    and old.message == message_text
    and old.title == title
    and old.source == source
    and old.level == level
    and old.details == details
    and old.icon == icon
    and old.markdown == markdown
  state.serial = state.serial + 1
  local notice = {
    id = id,
    kind = "notification",
    message = message_text,
    level = level,
    title = title,
    source = source,
    display = display,
    details = details,
    icon = icon,
    markdown = markdown,
    count = same and ((old.count or 1) + (not explicit and 1 or 0)) or 1,
    time = os.time(),
    order = old and old.order or state.serial,
    content_revision = old
        and old.message == message_text
        and old.details == details
        and old.markdown == markdown
        and old.content_revision
      or state.serial,
    revision = state.serial,
    timeout = timeout,
    paused = old and old.paused or nil,
    remaining = old and old.paused and timeout > 0 and timeout or nil,
    expires = not (old and old.paused) and timeout > 0 and (now + timeout) or nil,
  }
  state.notices[id] = notice
  M.archive(state, notice)
  M.trim(state, state.notices)
  return id, filter_error
end

function M.find_notice(state, id)
  if id ~= nil then
    if state.notices[id] then
      return state.notices[id]
    end
    for i = #state.history, 1, -1 do
      if state.history[i].id == id then
        return state.history[i]
      end
    end
    return nil
  end
  local latest
  local function consider(item)
    if
      item.kind ~= "task"
      and (not latest or (item.revision or item.order) > (latest.revision or latest.order))
    then
      latest = item
    end
  end
  for _, item in ipairs(state.history) do
    consider(item)
  end
  for _, item in pairs(state.notices) do
    consider(item)
  end
  return latest
end

function M.update_task(task, opts)
  local history = opts.history ~= nil and config.task_history(opts.history)
  local percentage
  if opts.percentage ~= nil then
    local value = opts.percentage
    assert(
      type(value) == "number" and value == value and math.abs(value) < math.huge,
      "percentage must be finite"
    )
    percentage = math.floor(math.max(0, math.min(100, value)))
  end
  for _, key in ipairs({ "title", "message", "source" }) do
    if opts[key] ~= nil then
      task[key] = M.text(opts[key])
    end
  end
  if percentage ~= nil then
    task.percentage = percentage
  end
  if opts.history ~= nil then
    task.history = history
  end
  task.updated = M.now()
end

function M.new_task(state, id, opts)
  state.serial = state.serial + 1
  local task = {
    id = id,
    title = "Working",
    message = "",
    source = "",
    history = state.config.progress.history,
    order = state.serial,
    started = M.now(),
  }
  M.update_task(task, opts)
  return task
end

function M.set_dnd(state, enabled)
  assert(type(enabled) == "boolean", "dnd must be a boolean")
  state.dnd = enabled
  if enabled then
    for _, notice in pairs(state.notices) do
      if notice.level < state.config.notification.dnd_level then
        notice.display = false
      end
    end
  end
  return enabled
end

function M.dismiss(state, id)
  if id == nil then
    state.notices = {}
  else
    state.notices[M.valid_id(id)] = nil
  end
end

function M.clear_history(state)
  state.history = {}
end
function M.clear_tasks(state)
  state.tasks = {}
end

function M.add_task(state, task, handle)
  state.tasks[task.id], task.handle = task, handle
  M.trim(state, state.tasks)
end

function M.tasks(state)
  local result = {}
  for _, task in ipairs(M.sorted(state.tasks)) do
    local copy = {}
    for key, value in pairs(task) do
      if key ~= "handle" then
        copy[key] = value
      end
    end
    result[#result + 1] = copy
  end
  return result
end

function M.history(state, opts)
  return vim.deepcopy(records.filter(state.history, opts))
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

function M.pause(notice)
  if notice.paused then
    return
  end
  if notice.expires then
    local remaining = notice.expires - M.now()
    if remaining <= 0 then
      return
    end
    notice.remaining, notice.expires = remaining, nil
  end
  notice.paused = true
end

function M.resume(notice)
  if not notice.paused then
    return
  end
  if notice.remaining then
    notice.expires = M.now() + notice.remaining
  end
  notice.paused, notice.remaining = nil, nil
end

-- One terminal transition for explicit completion and inactivity timeouts.
function M.finish_task(state, task, message, status)
  status = status or "success"
  assert(vim.tbl_contains({ "success", "error", "cancelled" }, status), "invalid task status")
  message = M.text(
    message or (status == "success" and "Completed" or status == "error" and "Error" or "Cancelled")
  )
  local now = M.now()
  task.done, task.finished, task.status, task.message = true, now, status, message
  if status == "success" and task.percentage then
    task.percentage = 100
  end
  task.expires = now + state.config.progress.done_ttl
  task.lifetime = state.config.progress.done_ttl
  if
    state.config.history_size == 0
    or task.history == false
    or (task.history == "errors" and status ~= "error")
  then
    return
  end
  local duration = math.max(0, now - task.started)
  local labels = { success = "Completed", error = "Failed", cancelled = "Cancelled" }
  local levels =
    { success = vim.log.levels.INFO, error = vim.log.levels.ERROR, cancelled = vim.log.levels.WARN }
  state.serial = state.serial + 1
  M.archive(state, {
    id = M.id(),
    kind = "task",
    task_id = task.id,
    title = task.title,
    source = task.source ~= "" and task.source or task.title,
    message = task.message,
    details = string.format("%s · %.1fs", labels[status], duration / 1000),
    level = levels[status],
    status = status,
    duration = duration,
    markdown = false,
    time = os.time(),
    order = state.serial,
    count = 1,
    timeout = 0,
    display = false,
  })
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
        M.finish_task(state, task, "Timed out", "error")
      end
    end
  end
end

-- Compute deadlines independently of drawing. Hidden items still expire, but
-- only visible items require animation/fade frames.
function M.next_delay(state, visible)
  visible = visible or { notices = {}, tasks = {} }
  local now, next_at = M.now(), nil
  local function wake(at)
    if at and (not next_at or at < next_at) then
      next_at = at
    end
  end
  local frame = math.min(33, state.config.progress.interval)
  local function expiry(item, fade, shown)
    wake(item.expires)
    if item.expires and shown and fade > 0 then
      local start = item.expires - math.min(fade, item.timeout or item.lifetime or fade)
      wake(now < start and start or math.min(item.expires, now + frame))
    end
  end
  for id, notice in pairs(state.notices) do
    expiry(notice, state.config.notification.fade_out, visible.notices[id])
  end
  local p = state.config.progress
  for id, task in pairs(state.tasks) do
    local shown = visible.tasks[id]
    expiry(task, p.fade_out, shown)
    if not task.done then
      if p.stale_timeout > 0 then
        wake(task.updated + p.stale_timeout)
      end
      if shown then
        if #p.spinner > 1 then
          wake((math.floor(now / p.interval) + 1) * p.interval)
        end
        if p.show_elapsed and task.percentage == nil then
          local age = math.max(0, now - task.started)
          local step = age < 60000 and 100 or age < 3600000 and 1000 or 60000
          wake(task.started + (math.floor(age / step) + 1) * step)
        end
      end
    end
  end
  return next_at and math.max(1, next_at - now) or nil
end

return M
