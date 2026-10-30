local h = dofile("tests/helpers.lua")
local original = vim.notify
local tools = require("notification-tools")
h.eq(original, vim.notify)
for _, autocmd in ipairs(vim.api.nvim_get_autocmds({})) do
  assert(autocmd.group_name ~= "NotificationTools")
end

tools.setup({
  history_size = 3,
  timeout = 45,
  progress = { done_ttl = 30, stale_timeout = 60, interval = 16 },
})
assert(vim.notify ~= original)
assert(not pcall(tools.setup, { timeout = -1 }))
assert(not pcall(tools.setup, { progress = { spinner = {} } }))
assert(not pcall(tools.notify, "bad", "invalid"))
assert(not pcall(tools.notify, "bad", nil, { timeout = math.huge }))
h.eq(nil, tools.notify("filtered", "debug"))
h.eq(nil, tools.notify("off", vim.log.levels.OFF))
-- Snapshot reads must also be safe before the history UI has ever been loaded.
local fast_snapshot
local snapshot_timer = vim.uv.new_timer()
snapshot_timer:start(1, 0, function()
  fast_snapshot = tools.history({ level = "warn" })
  snapshot_timer:close()
end)
h.wait(function()
  return fast_snapshot ~= nil
end)
h.eq({}, fast_snapshot)
h.eq(0, #tools.history())
local id = vim.notify("中文信息", nil, { title = "Build", timeout = 0 })
h.eq(id, tools.notify("updated", "warn", { replace = id, timeout = 0 }))
h.eq(1, #tools.history())
h.eq("Build", tools.history()[1].title)
local copy = tools.history()
copy[1].message = "changed"
h.eq("updated", tools.history()[1].message)
for i = 1, 4 do
  tools.notify("message " .. i)
end
h.eq(3, #tools.history())
h.wait(function()
  return #h.floats() == 1
end)
tools.dismiss(id)
h.wait(function()
  return #h.floats() == 0
end)
h.eq(3, #tools.history())

local task = tools.progress({ id = "build", title = "Build", percentage = 5 })
h.eq(task, tools.progress({ id = "build", message = "Compiling" }))
task:update({ percentage = 150 })
h.eq(100, tools.tasks()[1].percentage)
h.eq("Compiling", tools.tasks()[1].message)
assert(not pcall(task.update, task, { percentage = 0 / 0 }))
task:finish("Failed", "error")
h.eq("error", tools.tasks()[1].status)
task:update({ message = "must not change" })
h.eq("Failed", tools.tasks()[1].message)
h.wait(function()
  return #tools.tasks() == 0
end)
tools.progress({ title = "stale" })
h.wait(function()
  local tasks = tools.tasks()
  return tasks[1] and tasks[1].message == "Timed out"
end)
h.wait(function()
  return #tools.tasks() == 0
end)

local stale = tools.progress({ id = "old" })
tools.setup({ notify = false, max_pending = 2, history_size = 0 })
h.eq(original, vim.notify)
stale:update({ message = "late update" }):finish()
h.eq({}, tools.tasks())
for i = 1, 5 do
  tools.progress({ title = tostring(i) })
  tools.notify(tostring(i), nil, { timeout = 0 })
end
h.eq(2, #tools.tasks())
h.eq(0, #tools.history())
h.wait(function()
  return #h.floats() == 3
end)
tools.clear_tasks()
h.eq({}, tools.tasks())
tools.dismiss()
h.wait(function()
  return #h.floats() == 0
end)

-- The notify entry point must also work from libuv callbacks.
local timer = vim.uv.new_timer()
local fast_id
timer:start(1, 0, function()
  fast_id = tools.notify("fast callback", "info", { timeout = 0 })
  timer:close()
end)
h.wait(function()
  return fast_id and #h.floats() == 1
end)
tools.show_history()
h.wait(function()
  return vim.bo.filetype == "notification-tools-history"
end)
vim.api.nvim_feedkeys("q", "x", false)
h.wait(function()
  return vim.bo.filetype ~= "notification-tools-history"
end)

tools.setup()
local successor = function() end
vim.notify = successor
tools.teardown()
h.eq(successor, vim.notify)
vim.notify = original
tools.setup()
tools.notify("queued render")
tools.teardown()
vim.wait(60, function()
  return false
end, 10)
h.eq(0, #h.floats())
h.eq(original, vim.notify)
print("core: notification, history, task lifecycle, fast events and teardown passed")
