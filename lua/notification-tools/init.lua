local M = {}
local model = require("notification-tools.state")
local config = require("notification-tools.config")
local uv = vim.uv or vim.loop
local state, timer, group, previous_notify, owned_notify
local queued = false
local generation = 0

local function stop_timer()
  if timer then
    timer:stop()
    timer:close()
    timer = nil
  end
end

local function render()
  if not state then
    return
  end
  model.expire(state)
  require("notification-tools.integrations").prune()
  require("notification-tools.view").render(state)
  local needs_timer = false
  for _, notice in pairs(state.notices) do
    needs_timer = needs_timer or notice.expires ~= nil
  end
  for _, task in pairs(state.tasks) do
    needs_timer = needs_timer
      or task.expires ~= nil
      or (
        not task.done
        and (state.config.progress.enabled or state.config.progress.stale_timeout > 0)
      )
  end
  if not needs_timer then
    stop_timer()
  end
end

local function request_render()
  if queued then
    return
  end
  queued = true
  local current = generation
  vim.schedule(function()
    if current == generation then
      queued = false
      render()
    end
  end)
end

local function changed()
  request_render()
  if not timer then
    timer = assert(uv.new_timer())
    local interval = math.min(33, state.config.progress.interval)
    timer:start(interval, interval, request_render)
  end
end

local function ensure()
  if not state then
    M.setup()
  end
end

local function text(value)
  return type(value) == "table" and vim.inspect(value) or tostring(value or "")
end

local function valid_id(id)
  assert(type(id) == "string" or type(id) == "number", "id must be a string or number")
  assert(type(id) ~= "number" or (id == id and math.abs(id) < math.huge), "id must be finite")
  return id
end

local function trim(items)
  local sorted = model.sorted(items)
  for i = state.config.max_pending + 1, #sorted do
    items[sorted[i].id] = nil
  end
end

---Display a top-right notification. timeout=0 pins it until dismissed.
---@return string|number|nil id
function M.notify(message, level, opts)
  ensure()
  opts = opts or {}
  local explicit = opts.id ~= nil or opts.replace ~= nil
  local id = opts.id or opts.replace
  if type(id) == "table" then
    id = id.id
  end
  if id ~= nil then
    valid_id(id)
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
  local message_text = text(message)
  local title = text(opts.title or (old and old.title) or "Notification")
  local details = opts.details ~= nil and text(opts.details) or (old and old.details) or ""
  local icon = opts.icon or (old and old.icon)
  local now = model.now()
  if not explicit and state.config.notification.merge_duplicates then
    for _, item in ipairs(model.sorted(state.notices)) do
      if
        (not item.expires or item.expires > now)
        and item.message == message_text
        and item.title == title
        and item.details == details
        and item.level == level
        and item.icon == icon
        and item.timeout == timeout
      then
        old, id = item, item.id
        break
      end
    end
  end
  id = id or model.id()
  local same = old
    and old.message == message_text
    and old.title == title
    and old.level == level
    and old.details == details
    and old.icon == icon
  state.serial = state.serial + 1
  local notice = {
    id = id,
    message = message_text,
    level = level,
    title = title,
    details = details,
    icon = icon,
    count = same and ((old.count or 1) + (not explicit and 1 or 0)) or 1,
    time = os.time(),
    order = old and old.order or state.serial,
    timeout = timeout,
    expires = timeout > 0 and (now + timeout) or nil,
  }
  state.notices[id] = notice
  model.archive(state, notice)
  trim(state.notices)
  changed()
  return id
end

---Dismiss one notification, or all notifications. History and tasks are retained.
function M.dismiss(id)
  ensure()
  if id == nil then
    state.notices = {}
  else
    state.notices[valid_id(id)] = nil
  end
  request_render()
end

---Return an independent, oldest-first snapshot.
function M.history()
  ensure()
  return vim.deepcopy(state.history)
end

function M.clear_history()
  ensure()
  state.history = {}
end

function M.show_history()
  ensure()
  local current = generation
  vim.schedule(function()
    if current == generation then
      require("notification-tools.view").history(M.history())
    end
  end)
end

local function update_task(task, opts)
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
      task[key] = text(opts[key])
    end
  end
  if percentage ~= nil then
    task.percentage = percentage
  end
  task.updated = model.now()
end

---Create or retrieve a bottom-right task. Handles are inert after teardown/replacement.
function M.progress(opts)
  ensure()
  opts = opts or {}
  local id = valid_id(opts.id or model.id())
  local task = state.tasks[id]
  if task and not task.done then
    task.handle:update(opts)
    return task.handle
  end
  state.serial = state.serial + 1
  task = {
    id = id,
    title = "Working",
    message = "",
    source = "",
    order = state.serial,
    started = model.now(),
  }
  update_task(task, opts)
  local owner = state
  local handle = { id = id }
  local function alive()
    return state == owner and state.tasks[id] == task and not task.done
  end
  function handle:is_active()
    return alive()
  end
  function handle:update(update)
    if alive() then
      update_task(task, update or {})
      changed()
    end
    return self
  end
  function handle:finish(message, status)
    if alive() then
      status = status or "success"
      assert(vim.tbl_contains({ "success", "error", "cancelled" }, status), "invalid task status")
      task.done = true
      task.finished = model.now()
      task.status = status
      task.message = text(
        message
          or (status == "success" and "Completed" or status == "error" and "Error" or "Cancelled")
      )
      if status == "success" and task.percentage then
        task.percentage = 100
      end
      task.expires = model.now() + state.config.progress.done_ttl
      task.lifetime = state.config.progress.done_ttl
      changed()
    end
    return self
  end
  function handle:cancel(message)
    return self:finish(message, "cancelled")
  end
  state.tasks[id] = task
  task.handle = handle
  trim(state.tasks)
  changed()
  return handle
end

function M.tasks()
  ensure()
  local items = model.sorted(state.tasks)
  local result = {}
  for _, task in ipairs(items) do
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

function M.clear_tasks()
  ensure()
  state.tasks = {}
  require("notification-tools.integrations").reset()
  request_render()
end

function M.teardown()
  generation = generation + 1
  queued = false
  stop_timer()
  if group then
    pcall(vim.api.nvim_del_augroup_by_id, group)
    group = nil
  end
  if owned_notify and vim.notify == owned_notify then
    vim.notify = previous_notify
  end
  owned_notify, previous_notify = nil, nil
  if package.loaded["notification-tools.view"] then
    require("notification-tools.view").close()
    require("notification-tools.view").close_history()
  end
  if package.loaded["notification-tools.integrations"] then
    require("notification-tools.integrations").reset()
  end
  for _, name in ipairs({
    "Notifications",
    "NotificationsDismiss",
    "NotificationsClear",
    "NotificationToolsDemo",
  }) do
    pcall(vim.api.nvim_del_user_command, name)
  end
  state = nil
end

function M.setup(opts)
  -- Validate before replacing a working instance.
  local resolved = config.resolve(opts)
  M.teardown()
  state = model.new(resolved)
  local view = require("notification-tools.view")
  view.highlights()
  group = vim.api.nvim_create_augroup("NotificationTools", { clear = true })
  vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = view.highlights })
  vim.api.nvim_create_autocmd({ "VimResized", "UIEnter", "TabEnter", "WinEnter", "BufEnter" }, {
    group = group,
    callback = request_render,
  })
  vim.api.nvim_create_autocmd("OptionSet", {
    group = group,
    pattern = { "cmdheight", "laststatus", "showtabline" },
    callback = request_render,
  })
  vim.api.nvim_create_autocmd("VimLeavePre", { group = group, callback = M.teardown })
  require("notification-tools.integrations").setup(M, resolved, group)
  vim.api.nvim_create_user_command(
    "Notifications",
    M.show_history,
    { desc = "Notification history", force = true }
  )
  vim.api.nvim_create_user_command("NotificationsDismiss", function()
    M.dismiss()
  end, { desc = "Dismiss visible notifications", force = true })
  vim.api.nvim_create_user_command(
    "NotificationsClear",
    M.clear_history,
    { desc = "Clear notification history", force = true }
  )
  vim.api.nvim_create_user_command(
    "NotificationToolsDemo",
    M.demo,
    { desc = "Preview notifications and tasks", force = true }
  )
  if resolved.notify then
    previous_notify = vim.notify
    owned_notify = function(...)
      return M.notify(...)
    end
    vim.notify = owned_notify
  end
  return M
end

function M.demo()
  ensure()
  for _ = 1, 2 do
    M.notify("文档编译完成", "info", { title = "texquill", details = "main.pdf · 12 pages" })
  end
  M.notify("Workspace library is incomplete", "warn", { title = "lua_ls" })
  local task = M.progress({ title = "Indexing workspace", source = "lua_ls", percentage = 0 })
  local build =
    M.progress({ title = "Generating preview", source = "Build", message = "Rendering pages" })
  local current = generation
  for i = 1, 5 do
    vim.defer_fn(function()
      if current == generation then
        task:update({ percentage = i * 20, message = "Processing files" })
        if i == 5 then
          task:finish()
          build:finish("Preview ready")
        end
      end
    end, i * 600)
  end
end

return M
