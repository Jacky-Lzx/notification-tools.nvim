local h = dofile("tests/helpers.lua")
local tools = require("notification-tools")
local config = require("notification-tools.config")
local model = require("notification-tools.state")
local ns = vim.api.nvim_create_namespace("notification-tools")

local function contains(entry, needle)
  return table.concat(entry.lines, "\n"):find(needle, 1, true) ~= nil
end
local function notice(needle)
  for _, entry in ipairs(h.floats()) do
    if contains(entry, needle) then
      return entry
    end
  end
end
local function marks(entry)
  return vim.api.nvim_buf_get_extmarks(entry.buf, ns, 0, -1, { details = true })
end

local resolved = config.resolve({
  window = { border = "double", winblend = 8 },
  notification = { window = { max_width = 35 } },
  progress = { window = { max_width = 40 } },
})
h.eq("double", resolved.notification.window.border)
h.eq("double", resolved.progress.window.border)
h.eq(35, resolved.notification.window.max_width)
h.eq(40, resolved.progress.window.max_width)
h.eq(8, resolved.progress.window.winblend)
assert(not pcall(config.resolve, { notification = { window = { padding = { horizontal = -1 } } } }))
assert(not pcall(config.resolve, { progress = { window = { max_width = math.huge } } }))
assert(not pcall(config.resolve, { notification = { fade_out = -1 } }))

vim.o.columns, vim.o.lines = 120, 50
tools.setup({
  notify = false,
  timeout = 0,
  notification = { timestamp = false },
  progress = { stale_timeout = 0 },
})
local first =
  tools.notify("Document generated", "info", { title = "Build", details = "main.pdf · 12 pages" })
tools.notify("Second notification", "warn", { title = "Server" })
h.wait(function()
  return #h.floats() == 2
end)
local one, two = notice("Document generated"), notice("Second notification")
assert(
  one.lines[1]:find("%S") and one.lines[#one.lines]:find("%S"),
  "notifications must have no vertical padding"
)
assert(
  one and two and one.config.row < two.config.row,
  "new notifications must append in creation order"
)
local row, width, win = one.config.row, one.config.width, one.win
h.eq(
  first,
  tools.notify("Document generated", "info", { title = "Build", details = "main.pdf · 12 pages" })
)
h.eq(2, #tools.history())
h.eq(2, tools.history()[2].count)
h.wait(function()
  return notice("Document generated") and contains(notice("Document generated"), "×2")
end)
one = notice("Document generated")
h.eq(row, one.config.row)
h.eq(win, one.win)
assert(contains(one, "main.pdf · 12 pages"))
local groups = {}
for _, mark in ipairs(marks(one)) do
  groups[mark[4].hl_group] = true
end
assert(
  groups.NotificationToolsINFO
    and groups.NotificationToolsTitle
    and groups.NotificationToolsBody
    and groups.NotificationToolsMeta,
  "icon, title, body and details need independent highlights"
)
tools.notify("Short", nil, { id = first })
h.wait(function()
  return notice("Short") ~= nil
end)
h.eq(win, notice("Short").win)
assert(notice("Short").config.width >= width, "updates must not shrink and rewrap neighbours")
h.eq(1, tools.history()[2].count)

-- Explicit IDs remain independent; opting out restores one record per call.
local explicit =
  tools.notify("Second notification", "warn", { id = "producer:independent", title = "Server" })
assert(explicit ~= tools.history()[1].id)
h.eq(3, #tools.history())
tools.setup({ notify = false, timeout = 0, notification = { merge_duplicates = false } })
assert(tools.notify("Repeat") ~= tools.notify("Repeat"))
h.eq(2, #tools.history())
tools.dismiss()

-- Grouping keeps source labels out of task titles, aligns metadata, and is compact.
local a =
  tools.progress({ title = "Index", source = "lua_ls", percentage = 5, message = "Reading" })
local b = tools.progress({ title = "Check", source = "lua_ls", percentage = 100 })
tools.progress({ title = "Build", source = "texquill", message = "Compiling" })
h.wait(function()
  return notice("Index") ~= nil
end)
local panel = notice("Index")
assert(panel.config.border and panel.config.border ~= "none" and #panel.config.border > 0)
assert(panel.config.width < 60)
local text = table.concat(panel.lines, "\n")
local _, count = text:gsub("lua_ls", "")
h.eq(1, count)
local index_row, check_row, index_percent, check_percent
for i, line in ipairs(panel.lines) do
  if line:find("Index", 1, true) then
    index_row = i
    index_percent = vim.fn.strdisplaywidth(line:match("^(.-)5%%")) + 2
  elseif line:find("Check", 1, true) then
    check_row = i
    check_percent = vim.fn.strdisplaywidth(line:match("^(.-)100%%")) + 4
  end
end
assert(index_row < check_row)
h.eq(index_percent, check_percent)
local before_win, before_row = panel.win, panel.config.row
a:update({ percentage = 65, message = "Parsing" })
h.wait(function()
  return contains(notice("Index"), "65%")
end)
panel = notice("Index")
h.eq(before_win, panel.win)
h.eq(before_row, panel.config.row)
assert(contains(panel, "Parsing"))
for _, mark in ipairs(marks(panel)) do
  assert(
    mark[2] < #panel.lines and mark[3] < #panel.lines[mark[2] + 1],
    "updated extmarks must stay on their text"
  )
end
b:cancel()
h.wait(function()
  for _, mark in ipairs(marks(notice("Index"))) do
    if mark[4].hl_group == "NotificationToolsCancelled" then
      return true
    end
  end
end)
tools.teardown()

-- Clock-controlled fade checks avoid a flaky wall-clock assertion and ensure a
-- completed task fades independently of active siblings, without changing TTL.
local clock = model.now
local now = 1000
model.now = function()
  return now
end
tools.setup({
  notify = false,
  timeout = 1000,
  notification = { fade_out = 200 },
  progress = { done_ttl = 1000, fade_out = 200, stale_timeout = 0 },
})
vim.api.nvim_set_hl(0, "NotificationToolsNormal", { fg = 0xffffff, bg = 0x101010 })
vim.api.nvim_set_hl(0, "NotificationToolsTaskTitle", {})
vim.api.nvim_set_hl(0, "NotificationToolsTaskTitle", { default = true, fg = 0xffffff })
tools.notify("Fading notice")
local done = tools.progress({ title = "Finished", source = "jobs" })
tools.progress({ title = "Still active", source = "jobs" })
done:finish()
h.wait(function()
  return notice("Finished") and notice("Fading notice")
end)
local stable = notice("Finished").win
now = 1900
vim.api.nvim_exec_autocmds("VimResized", {})
h.wait(function()
  return vim.wo[notice("Fading notice").win].winblend >= 45
end)
local done_fades, active_plain, fade_group = false, false
for _, mark in ipairs(marks(notice("Finished"))) do
  local group = mark[4].hl_group
  done_fades = done_fades or group:find("TaskTitleFade", 1, true) ~= nil
  if group:find("TaskTitleFade", 1, true) then
    fade_group = group
  end
  active_plain = active_plain or group == "NotificationToolsTaskTitle"
end
assert(done_fades and active_plain)
h.eq(0x888888, vim.api.nvim_get_hl(0, { name = fade_group, link = false }).fg)
vim.api.nvim_set_hl(0, "NotificationToolsProgressNormal", { fg = 0xffffff, bg = 0x303030 })
vim.api.nvim_exec_autocmds("VimResized", {})
h.wait(function()
  return vim.api.nvim_get_hl(0, { name = fade_group, link = false }).fg == 0x989898
end)
h.eq(0, vim.wo[stable].winblend)
h.eq(2, #tools.tasks())
now = 2001
vim.api.nvim_exec_autocmds("VimResized", {})
h.wait(function()
  return #tools.tasks() == 1 and #h.floats() == 1
end)
h.eq(stable, notice("Still active").win)
h.eq(1, #tools.history())
tools.teardown()
model.now = clock
tools.setup({ notify = false })
for _, theme in ipairs({ "morning", "evening" }) do
  vim.cmd.colorscheme(theme)
  local text = vim.api.nvim_get_hl(0, { name = "NotificationToolsBody", link = false })
  local float = vim.api.nvim_get_hl(0, { name = "NormalFloat", link = false })
  local normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
  h.eq(float.fg or normal.fg, text.fg)
  h.eq(nil, text.bg)
end
tools.teardown()
print(
  "styles: split options, notification merging, byte highlights, grouped layout, stable updates and independent fades passed"
)
