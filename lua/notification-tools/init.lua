---@class notification_tools.API
local M = {}
local model = require("notification-tools.state")
local config = require("notification-tools.config")
local state, scheduler, group, previous_notify, owned_notify
local generation = 0
local view_ready = false

-- Entry points/state stay available at startup; presentation loads on demand.
local function get_view()
  local view = require("notification-tools.view")
  if not view_ready then
    view.highlights()
    view_ready = true
  end
  return view
end

local function wants_view()
  for _, notice in pairs(state.notices) do
    if notice.display ~= false then
      return true
    end
  end
  return state.config.progress.enabled
    and next(state.tasks) ~= nil
    and not vim.tbl_contains(state.config.progress.avoid, vim.bo.filetype)
end

local function render()
  if not state then
    return
  end
  model.expire(state)
  require("notification-tools.integrations").prune()
  local visible = { notices = {}, tasks = {}, bars = {} }
  if view_ready or wants_view() then
    visible = get_view().render(state)
  end
  return model.next_delay(state, visible)
end

local function request_render()
  if scheduler then
    scheduler:request()
  end
end

local changed = request_render

local function ensure()
  if not state then
    M.setup()
  end
end

---Display a top-right notification. timeout=0 pins it until dismissed.
---@param message any Strings are displayed directly; tables use vim.inspect.
---@param level? notification_tools.Level
---@param opts? notification_tools.NotifyOptions
---@return notification_tools.ID? id Nil when filtered or discarded.
function M.notify(message, level, opts)
  ensure()
  local owner, current = state, generation
  local id, filter_error = model.notify(owner, message, level, opts)
  if state ~= owner then
    return nil
  end
  if filter_error then
    vim.schedule(function()
      if current == generation then
        vim.api.nvim_err_writeln("notification-tools filter: " .. filter_error)
      end
    end)
  end
  if id then
    changed()
  end
  return id
end

---DND only affects ordinary popups. Suppressed notices are not replayed.
---@param enabled boolean
---@return boolean enabled
function M.set_dnd(enabled)
  ensure()
  local result = model.set_dnd(state, enabled)
  request_render()
  return result
end

---@return boolean enabled
function M.is_dnd()
  ensure()
  return state.dnd
end

---@return boolean enabled
function M.toggle_dnd()
  return M.set_dnd(not M.is_dnd())
end

---Dismiss one notification, or all notifications. History and tasks are retained.
---@param id? notification_tools.ID Omit to dismiss all ordinary notifications.
function M.dismiss(id)
  ensure()
  model.dismiss(state, id)
  request_render()
end

---Return an independent, oldest-first snapshot.
---@param opts? notification_tools.HistoryFilters
---@return notification_tools.Record[] records Independent, oldest-first snapshots.
function M.history(opts)
  ensure()
  return model.history(state, opts)
end

---Clear retained notification and task-result history.
function M.clear_history()
  ensure()
  model.clear_history(state)
end

local function reading_zindex()
  return math.max(state.config.notification.window.zindex, state.config.progress.window.zindex) + 1
end

---@param opts? notification_tools.HistoryFilters
function M.show_history(opts)
  ensure()
  opts = require("notification-tools.records").options(opts)
  local current = generation
  vim.schedule(function()
    if current == generation then
      get_view().history(function()
        return state.history
      end, opts, M.show_notification, reading_zindex())
    end
  end)
end

---Read a complete notice; an active notice's remaining timeout pauses until closed.
---@param id? notification_tools.ID Omit to read the latest ordinary notification.
---@return notification_tools.ID? id Nil when unavailable; display is scheduled.
function M.show_notification(id)
  ensure()
  if id ~= nil then
    model.valid_id(id)
  end
  local item = model.find_notice(state, id)
  if not item then
    return nil
  end
  local snapshot, owner, current = vim.deepcopy(item), state, generation
  id = item.id
  vim.schedule(function()
    if current ~= generation then
      return
    end
    local view = get_view()
    view.close_history() -- resume the previous reader before pausing this one
    local active = state.notices[id]
    if active then
      model.pause(active)
    end
    local function resume()
      if state == owner and current == generation then
        local notice = state.notices[id]
        if notice then
          model.resume(notice)
        end
        changed()
      end
    end
    local ok, err = pcall(view.notification, function()
      return { model.find_notice(state, id) or snapshot }
    end, resume, reading_zindex())
    if not ok then
      resume()
      error(err)
    end
    changed()
  end)
  return id
end

---Create or retrieve a bottom-right task. Handles are inert after teardown/replacement.
---@param opts? notification_tools.TaskOptions
---@return notification_tools.TaskHandle handle
function M.progress(opts)
  ensure()
  opts = opts or {}
  local id = model.valid_id(opts.id or model.id())
  local task = state.tasks[id]
  if task and not task.done then
    task.handle:update(opts)
    return task.handle
  end
  task = model.new_task(state, id, opts)
  local current = generation
  local handle = { id = id }
  local function alive()
    return generation == current and state ~= nil and state.tasks[id] == task and not task.done
  end
  ---@return boolean
  function handle:is_active()
    return alive()
  end
  ---@param update? notification_tools.TaskUpdate
  ---@return notification_tools.TaskHandle
  function handle:update(update)
    if alive() then
      model.update_task(task, update or {})
      changed()
    end
    return self
  end
  ---@param message? string
  ---@param status? notification_tools.TaskStatus
  ---@return notification_tools.TaskHandle
  function handle:finish(message, status)
    if alive() then
      model.finish_task(state, task, message, status)
      changed()
    end
    return self
  end
  ---@param message? string
  ---@return notification_tools.TaskHandle
  function handle:cancel(message)
    return self:finish(message, "cancelled")
  end
  model.add_task(state, task, handle)
  changed()
  return handle
end

---@return notification_tools.TaskSnapshot[] tasks Independent, newest-first snapshots.
function M.tasks()
  ensure()
  return model.tasks(state)
end

---Clear task state and invalidate all active producer handles.
function M.clear_tasks()
  ensure()
  model.clear_tasks(state)
  require("notification-tools.integrations").reset()
  request_render()
end

---Release owned resources and restore vim.notify only while still owned.
function M.teardown()
  generation = generation + 1
  if scheduler then
    scheduler:close()
    scheduler = nil
  end
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
    require("notification-tools.layout").reset()
  end
  if package.loaded["notification-tools.integrations"] then
    require("notification-tools.integrations").reset()
  end
  if package.loaded["notification-tools.commands"] then
    require("notification-tools.commands").clear()
  end
  state = nil
  view_ready = false
end

---@param opts? notification_tools.Config
---@return notification_tools.API
function M.setup(opts)
  -- Validate before replacing a working instance.
  local resolved = config.resolve(opts)
  M.teardown()
  state = model.new(resolved)
  scheduler =
    require("notification-tools.scheduler").new(render, math.min(33, resolved.progress.interval))
  group = vim.api.nvim_create_augroup("NotificationTools", { clear = true })
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = function()
      if view_ready then
        get_view().highlights()
        request_render()
      end
    end,
  })
  vim.api.nvim_create_autocmd({ "VimResized", "UIEnter", "WinEnter", "BufEnter" }, {
    group = group,
    callback = request_render,
  })
  vim.api.nvim_create_autocmd("TabEnter", {
    group = group,
    callback = function()
      if package.loaded["notification-tools.history"] then
        require("notification-tools.history").close_hidden()
      end
      request_render()
    end,
  })
  vim.api.nvim_create_autocmd("OptionSet", {
    group = group,
    pattern = { "cmdheight", "laststatus", "showtabline", "ambiwidth", "emoji" },
    callback = request_render,
  })
  vim.api.nvim_create_autocmd("VimLeavePre", { group = group, callback = M.teardown })
  require("notification-tools.integrations").setup(M, resolved, group)
  require("notification-tools.commands").setup(M)
  if resolved.notify then
    previous_notify = vim.notify
    owned_notify = function(...)
      return M.notify(...)
    end
    vim.notify = owned_notify
  end
  return M
end

---Preview notification cards and task progress using the public API.
function M.demo()
  ensure()
  for _ = 1, 2 do
    M.notify("Document compiled", "info", { title = "texquill", details = "main.pdf · 12 pages" })
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
