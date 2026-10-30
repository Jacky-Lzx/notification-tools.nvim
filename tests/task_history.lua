local h = dofile("tests/helpers.lua")
local tools = require("notification-tools")
local model = require("notification-tools.state")
local now = 1000
model.now = function()
  return now
end
local function expire()
  vim.api.nvim_exec_autocmds("VimResized", {})
  vim.wait(50, function()
    return false
  end, 10)
end

tools.setup({ notify = false, progress = { done_ttl = 0, stale_timeout = 100 } })
tools.progress({ title = "Success" }):finish()
tools.progress({ title = "Cancelled" }):cancel()
h.eq(0, #tools.history())
local failed = tools.progress({ id = "build", title = "Build", source = "compiler" })
-- Avoid a halfway rounding case, which differs across LuaJIT builds.
now = 2260
failed:finish("Missing file", "error")
failed:finish("ignored", "error"):cancel()
h.eq(1, #tools.history())
local entry = tools.history()[1]
h.eq("task", entry.kind)
h.eq("build", entry.task_id)
h.eq("compiler", entry.source)
h.eq("Missing file", entry.message)
h.eq("Failed · 1.3s", entry.details)
h.eq(1260, entry.duration)
h.eq("error", entry.status)
h.eq(vim.log.levels.ERROR, entry.level)
expire()
h.eq(0, #tools.tasks())
h.eq(0, #h.floats()) -- records do not create a second popup
h.eq(1, #tools.history())
-- Reused producer IDs create distinct records, never overwriting an earlier run.
tools
  .progress({ id = "build", title = "Build", source = "compiler" })
  :finish("Second failure", "error")
h.eq(2, #tools.history())
assert(tools.history()[1].id ~= tools.history()[2].id)
local stale = tools.progress({ id = "stale", title = "Silent" })
now = now + 101
expire()
h.eq("Timed out", tools.history()[3].message)
assert(not stale:is_active())
expire()
h.eq(3, #tools.history())
tools.show_history({ source = "compiler", level = "error" })
h.wait(function()
  return vim.bo.filetype == "notification-tools-history"
end)
local text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
assert(text:find("Missing file", 1, true) and text:find("Second failure", 1, true))
assert(not text:find("Timed out", 1, true))
vim.api.nvim_feedkeys("q", "xt", false)

tools.setup({ notify = false, history_size = 2, progress = { history = "all" } })
tools.progress({ title = "Success" }):finish("Ready")
tools.progress({ title = "Cancel" }):cancel("User stopped")
h.eq("success", tools.history()[1].status)
h.eq(vim.log.levels.WARN, tools.history()[2].level)
tools.notify("ordinary", "info", { timeout = 0 })
h.eq(2, #tools.history())
h.eq("notification", tools.history()[2].kind)
-- Per-task opt-out and changing the policy on update are independent of defaults.
tools.progress({ title = "private", history = false }):finish("hidden", "error")
h.eq(2, #tools.history())
local opted = tools.progress({ title = "opt-in", history = false })
opted:update({ history = "all" }):finish("kept")
h.eq("opt-in", tools.history()[2].title)
local copy = tools.history()
copy[2].message = "mutated"
h.eq("kept", tools.history()[2].message)
assert(not pcall(tools.setup, { progress = { history = true } }))
assert(not pcall(tools.progress, { history = "invalid" }))
tools.setup({ notify = false, progress = { history = false } })
tools.progress({ title = "disabled" }):finish("hidden", "error")
h.eq(0, #tools.history())
tools.progress({ title = "opt-in", history = "all" }):finish()
h.eq(1, #tools.history())
local old = tools.progress({ title = "old" })
tools.clear_tasks()
old:finish("must not record", "error")
h.eq(1, #tools.history())
tools.setup({ notify = false, history_size = 0, progress = { history = "all" } })
tools.progress({ title = "no history" }):finish(nil, "error")
h.eq(0, #tools.history())
tools.teardown()
print(
  "task history: failure defaults, opt-out/opt-in, timeout records, unique runs, retention and history filters passed"
)
