local h = dofile("tests/helpers.lua")
local config = require("notification-tools.config")
local layout = require("notification-tools.layout")
local model = require("notification-tools.state")
local tools = require("notification-tools")
h.eq("bar", config.resolve().progress.style)
assert(not pcall(config.resolve, { progress = { style = "invalid" } }))
assert(not pcall(config.resolve, { progress = { style = false } }))
for _, option in ipairs({ "display_delay", "error_ttl" }) do
  assert(not pcall(config.resolve, { progress = { [option] = -1 } }))
  assert(not pcall(config.resolve, { progress = { [option] = 0.5 } }))
end
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
local c = config.resolve({
  progress = { spinner = { "." }, show_elapsed = false, stale_timeout = 0, display_delay = 0 },
})
local pending = task()
local first = layout.progress({ pending }, c, 44, 12, nil, 0)
local next_frame = layout.progress({ pending }, c, 44, 12, nil, 80)
h.eq(nil, bar_line(first))
h.eq(first, next_frame)
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
h.eq(nil, model.next_delay(state, { notices = {}, tasks = { test = true }, bars = {} }))
model.now = original
for _, status in ipairs({ "success", "error", "cancelled" }) do
  local ended = task(50, true, status)
  ended.finished = 1250
  ended.message = status == "success" and "Completed" or "Reason"
  local plan = layout.progress({ ended }, c, 44, 12, nil, 1300)
  h.eq(nil, bar_line(plan))
  local content = table.concat(plan.lines, "\n")
  assert(content:find("Build", 1, true))
  assert(not content:find("50%%") and not content:find("100%%"))
  if status == "success" then
    h.eq(2, #plan.lines)
    assert(not content:find("Completed", 1, true))
  else
    assert(content:find("Reason", 1, true))
  end
end
local compact = config.resolve({ progress = { style = "compact" } })
h.eq(nil, bar_line(layout.progress({ task(50) }, compact, 44, 12, nil, 0)))
h.eq(nil, bar_line(layout.progress({ task(50) }, c, 44, 1, nil, 0)))
-- Group equivalent successful results before applying row limits, without
-- merging producers or hiding distinct completion messages.
local duplicates = {}
for i = 1, 8 do
  local item = task(nil, true, "success")
  item.id, item.title, item.message, item.finished = i, "", "Completed", 2000
  duplicates[#duplicates + 1] = item
end
local grouped = layout.progress(duplicates, c, 44, 2, nil, 2100)
h.eq(2, #grouped.lines)
h.eq(8, grouped.displayed)
assert(table.concat(grouped.lines, "\n"):find("Completed ×8", 1, true))
for i = 1, 8 do
  assert(grouped.task_ids[i])
end
duplicates[2].message = "Document ready"
local distinct = layout.progress(duplicates, c, 44, 8, nil, 2100)
assert(table.concat(distinct.lines, "\n"):find("Document ready", 1, true))
assert(table.concat(distinct.lines, "\n"):find("Completed ×7", 1, true))
duplicates[2].message, duplicates[2].source = "Completed", "other"
local ungrouped = config.resolve({ progress = { group_by_source = false } })
local separate = layout.progress(duplicates, ungrouped, 44, 8, nil, 2100)
h.eq(2, #separate.lines)
assert(table.concat(separate.lines, "\n"):find("Completed ×7", 1, true))
local timed = task(100, true, "success")
timed.finished, timed.message = 1260, "Completed"
local duration =
  table.concat(layout.progress({ timed }, config.resolve(), 44, 8, nil, 5000).lines, "\n")
assert(duration:find("1.3s", 1, true))
assert(not duration:find("100%%"))
-- Public task semantics remain unchanged, including unknown completion percentages.
tools.setup({ notify = false, progress = { spinner = { "." }, show_elapsed = false } })
local handle = tools.progress({ title = "Known total", percentage = 25 })
h.wait(function()
  return #h.floats() == 1
end)
local before = assert(bar_line(h.floats()[1]))
handle:update({ percentage = 75 })
h.wait(function()
  return bar_line(h.floats()[1]) ~= before
end)
handle:finish()
h.eq(100, tools.tasks()[1].percentage)
tools.progress({ title = "Unknown total" }):finish()
h.eq(nil, tools.tasks()[1].percentage)
tools.teardown()
print(
  "progress bars: proportional fill, compact unknown/completed tasks, useful results and narrow fallback passed"
)
