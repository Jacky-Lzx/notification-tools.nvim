local h = dofile("tests/helpers.lua")
local tools = require("notification-tools")
local model = require("notification-tools.state")
local now = 1000
model.now = function()
  return now
end
local function settle(count)
  vim.wait(50, function()
    return false
  end, 10)
  h.eq(count, #h.floats())
end

tools.setup({ notify = false, timeout = 100, notification = { dnd = true } })
assert(tools.is_dnd())
local hidden = tools.notify("hidden", "info", { source = "build" })
local error_id = tools.notify("error", "error")
settle(1)
h.eq(2, #tools.history())
h.eq("build", tools.history()[1].source)
h.eq("Notification", tools.history()[2].source)
assert(hidden and error_id)
assert(not tools.toggle_dnd())
settle(1) -- no replay
local visible = tools.notify("visible", "info")
settle(2)
assert(tools.set_dnd(true))
settle(1) -- existing non-error popups close, error remains
assert(not tools.set_dnd(false))
settle(1)
tools.notify("updated", "info", { id = visible, source = "updated-source" })
settle(2)
h.eq("updated-source", tools.history()[#tools.history()].source)
local task = tools.progress({ title = "unaffected" })
settle(3)
tools.set_dnd(true)
settle(2) -- task and error
assert(task:is_active())
now = 1200
settle(1)

local seen = {}
tools.setup({
  notify = false,
  timeout = 0,
  notification = {
    filter = function(notice)
      seen[#seen + 1] = vim.deepcopy(notice)
      local decision = notice.source
      notice.message = "must not mutate the actual message"
      if decision == "log" then
        return "history"
      end
      if decision == "noise" then
        return "drop"
      end
      return "show"
    end,
  },
})
h.eq(nil, tools.notify("discard", "warn", { source = "noise" }))
local log = tools.notify("retained", "warn", { source = "log", title = "Compiler" })
local show = tools.notify("visible", "info", { source = "compiler" })
settle(1)
h.eq(2, #tools.history())
h.eq("retained", tools.history()[1].message)
h.eq("Compiler", tools.history()[1].title)
h.eq("discard", seen[1].message)
h.eq(log, tools.notify("retained", "warn", { source = "log", title = "Compiler" }))
h.eq(2, tools.history()[#tools.history()].count)
tools.notify("replacement", nil, { id = show })
h.eq("compiler", seen[#seen].source)
tools.notify("visible", "info", { source = "another" })
settle(2) -- source participates in deduplication
vim.cmd("NotificationsDnd on")
assert(tools.is_dnd())
settle(0)
vim.cmd("NotificationsDnd off")
assert(not tools.is_dnd())
settle(0)
assert(not pcall(vim.cmd, "NotificationsDnd invalid"))
assert(not pcall(tools.set_dnd, "yes"))
assert(not pcall(tools.setup, { notification = { filter = true } }))
assert(not pcall(tools.setup, { notification = { dnd_level = "nope" } }))
-- A broken filter must not recursively call vim.notify or lose the message.
tools.setup({
  notify = false,
  timeout = 0,
  notification = {
    filter = function()
      error("broken filter")
    end,
  },
})
tools.notify("fail open")
settle(1)
assert(vim.v.errmsg:find("broken filter", 1, true))
tools.teardown()
h.eq(nil, vim.api.nvim_get_commands({}).NotificationsDnd)
print(
  "routing: DND, no replay, source-aware merging, history-only/drop routes and callback isolation passed"
)
