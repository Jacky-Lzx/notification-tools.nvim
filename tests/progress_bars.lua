local h = dofile("tests/helpers.lua")
local config = require("notification-tools.config")
local layout = require("notification-tools.layout")
local model = require("notification-tools.state")
local tools = require("notification-tools")
h.eq("bar", config.resolve().progress.style)
assert(not pcall(config.resolve, { progress = { style = "invalid" } }))
assert(not pcall(config.resolve, { progress = { style = false } }))
local function task(percentage, done, status)
  return {
    id = "test",
    title = "Build",
    source = "compiler",
    message = "Working",
    started = 0,
    updated = 0,
    percentage = percentage,
    done = done,
    status = status,
  }
end
local function bar_line(plan)
  for _, line in ipairs(plan.lines) do
    if line:find("━", 1, true) or line:find("─", 1, true) then
      return line
    end
  end
end
local function count(line, char)
  local _, n = line:gsub(char, "")
  return n
end
for _, ambiwidth in ipairs({ "single", "double" }) do
  vim.o.ambiwidth = ambiwidth
  local c = config.resolve({ progress = { window = { min_width = 40, max_width = 40 } } })
  for _, percentage in ipairs({ 0, 25, 50, 100 }) do
    local plan = layout.progress({ task(percentage) }, c, 40, 12, nil, 0)
    local line = assert(bar_line(plan))
    local slots = count(line, "━") + count(line, "─")
    h.eq(math.floor(slots * percentage / 100), count(line, "━"))
    assert(plan.bar_tasks.test)
    for _, row in ipairs(plan.lines) do
      assert(vim.fn.strdisplaywidth(row) <= plan.width)
    end
  end
  for _, width in ipairs({ 4, 8, 12, 24 }) do
    for _, height in ipairs({ 1, 2, 4, 8 }) do
      local plan = layout.progress({ task(50) }, c, width, height, nil, 0)
      if plan then
        assert(#plan.lines <= height)
        for _, row in ipairs(plan.lines) do
          assert(vim.fn.strdisplaywidth(row) <= plan.width)
        end
      end
    end
  end
end
vim.o.ambiwidth = "single"
local c =
  config.resolve({ progress = { spinner = { "." }, show_elapsed = false, stale_timeout = 0 } })
local pending = task()
local first = layout.progress({ pending }, c, 44, 12, nil, 0)
local next_frame = layout.progress({ pending }, c, 44, 12, nil, 80)
assert(
  bar_line(first) ~= bar_line(next_frame),
  "unknown percentage must animate even with a single spinner frame"
)
assert(
  not table.concat(first.lines, "\n"):find("%%"),
  "indeterminate progress must not fabricate a percentage"
)
local state = model.new(c)
state.tasks.test = pending
local original = model.now
model.now = function()
  return 0
end
h.eq(80, model.next_delay(state, { notices = {}, tasks = { test = true }, bars = { test = true } }))
h.eq(nil, model.next_delay(state, { notices = {}, tasks = { test = true }, bars = {} }))
model.now = original
local complete =
  assert(bar_line(layout.progress({ task(nil, true, "success") }, c, 44, 12, nil, 0)))
h.eq(0, count(complete, "─"))
for _, status in ipairs({ "error", "cancelled" }) do
  local ended = task(50, true, status)
  local plan = layout.progress({ ended }, c, 44, 12, nil, 0)
  h.eq(bar_line(plan), bar_line(layout.progress({ ended }, c, 44, 12, nil, 80)))
  local colored = false
  for _, mark in ipairs(plan.marks) do
    local value = plan.lines[mark.row + 1]:sub(mark.col + 1, mark.finish)
    if value:find("━", 1, true) then
      h.eq(status == "error" and "ERROR" or "Cancelled", mark.hl)
      colored = true
    end
  end
  assert(colored)
end
local compact = config.resolve({ progress = { style = "compact" } })
h.eq(nil, bar_line(layout.progress({ task(50) }, compact, 44, 12, nil, 0)))
h.eq(nil, bar_line(layout.progress({ task(50) }, c, 44, 1, nil, 0)))
-- Public task semantics remain unchanged, including unknown completion percentages.
tools.setup({ notify = false, progress = { spinner = { "." }, show_elapsed = false } })
local handle = tools.progress({ title = "Unknown total" })
h.wait(function()
  return #h.floats() == 1
end)
local before = assert(bar_line(h.floats()[1]))
h.wait(function()
  return bar_line(h.floats()[1]) ~= before
end)
handle:finish()
h.eq(nil, tools.tasks()[1].percentage)
tools.teardown()
print(
  "progress bars: default style, proportional fill, unknown animation/deadlines, status colors and compact fallback passed"
)
