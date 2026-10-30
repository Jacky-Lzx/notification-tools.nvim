local h = dofile("tests/helpers.lua")
local tools = require("notification-tools")
local model = require("notification-tools.state")
local config = require("notification-tools.config")
local view = require("notification-tools.view")
local original_now = model.now
model.now = function()
  return 1000
end
local state = model.new(config.resolve({ progress = { stale_timeout = 0 } }))
state.notices.a = { expires = 5000, timeout = 4000 }
h.eq(3820, model.next_delay(state, { notices = { a = true }, tasks = {} }))
h.eq(4000, model.next_delay(state, { notices = {}, tasks = {} }))
state.notices = {}
state.tasks.a = { started = 1000, updated = 1000, percentage = 50 }
h.eq(40, model.next_delay(state, { notices = {}, tasks = { a = true } }))
h.eq(nil, model.next_delay(state, { notices = {}, tasks = {} }))
state.config.progress.stale_timeout = 300
h.eq(300, model.next_delay(state, { notices = {}, tasks = {} }))
state.tasks.a = { done = true, expires = 1120, lifetime = 1500 }
h.eq(33, model.next_delay(state, { notices = {}, tasks = { a = true } }))
model.now = original_now

local renders, render = 0, view.render
view.render = function(...)
  renders = renders + 1
  return render(...)
end
tools.setup({ notify = false, timeout = 5000, notification = { fade_out = 0 } })
tools.notify("Static until expiry")
h.wait(function()
  return #h.floats() == 1
end)
local before = renders
vim.wait(150, function()
  return false
end, 5)
h.eq(before, renders)
tools.setup({ notify = false, progress = { stale_timeout = 0 } })
vim.bo.filetype = "NvimTree"
tools.progress({ title = "Hidden" })
vim.wait(60, function()
  return false
end, 5)
before = renders
vim.wait(150, function()
  return false
end, 5)
h.eq(before, renders)
vim.bo.filetype = "lua"

-- A burst can update state frequently without repainting every input event.
tools.setup({ notify = false, progress = { spinner = { "·" }, stale_timeout = 0 } })
local task = tools.progress({ title = "Burst", percentage = 0 })
h.wait(function()
  return #h.floats() == 1
end)
renders = 0
local timer, updates = vim.uv.new_timer(), 0
timer:start(1, 1, function()
  updates = updates + 1
  task:update({ percentage = updates })
  if updates == 100 then
    timer:stop()
    timer:close()
  end
end)
h.wait(function()
  return updates == 100
end, 2500)
h.wait(function()
  return table.concat(h.floats()[1].lines, "\n"):find("100%%") ~= nil
end)
assert(renders < updates / 3, "bursts must be coalesced across event-loop turns")
h.eq(100, tools.tasks()[1].percentage)
tools.teardown()
view.render = render
print(
  "scheduler: static/hidden sleep, fade/expiry/stale deadlines and bounded burst repainting passed"
)
