local h = dofile("tests/helpers.lua")
local tools = require("notification-tools")
local model = require("notification-tools.state")
local now = 1000
model.now = function()
  return now
end
local function settle(count)
  vim.api.nvim_exec_autocmds("VimResized", {})
  vim.wait(50, function()
    return false
  end, 10)
  if count then
    h.eq(count, #h.floats())
  end
end
local function open(id)
  local result = tools.show_notification(id)
  h.wait(function()
    return vim.bo.filetype == "notification-tools-history"
  end)
  return vim.api.nvim_get_current_win(), result
end
local function key(keys)
  vim.api.nvim_feedkeys(keys, "xt", false)
end
local function contents()
  return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
end

tools.setup({ notify = false, timeout = 1000 })
h.eq(nil, tools.show_notification())
h.eq(nil, tools.show_notification("missing"))
local raw = "**Long notification**\n" .. string.rep("untruncated\n", 30) .. "last line"
local id = tools.notify(raw, "warn", { title = "Read" })
settle(1)
now = 1300
local win, shown = open(id)
h.eq(id, shown)
assert(contents():find(raw, 1, true), "reader must keep the entire raw message")
h.eq(2, vim.wo[win].conceallevel)
h.eq("c", vim.wo[win].concealcursor)
now = 5000
settle(1) -- a reader holds the original popup alive past its original deadline
key("q")
settle(1)
now = 5699
settle(1)
now = 5701
settle(0) -- 700ms remaining resumes on close, not a new full timeout
-- Expired notifications can still be read from history without resurrecting a popup.
open(id)
assert(contents():find("last line", 1, true))
key("q")
settle(0)

now = 6000
local updated = tools.notify("before", "info", { title = "Live" })
now = 6200
open(updated)
now = 9000
tools.notify("**after**", "info", { id = updated, timeout = 500 })
settle(1)
key("r")
assert(contents():find("**after**", 1, true))
now = 12000
settle(1) -- replacements while reading stay paused
vim.api.nvim_win_close(0, true) -- external close must release the pause
now = 12499
settle(1)
now = 12501
settle(0)

-- Opening another reader releases the first; dismissing never recreates it.
now = 13000
local a = tools.notify("a", nil, { timeout = 1000 })
local b = tools.notify("b", nil, { timeout = 1000 })
open(a)
now = 14001
open(b)
settle(1) -- b expired before reading, a was resumed on switching readers
now = 15002
settle(0)
key("q")
now = 16000
local dismissed = tools.notify("dismissed", nil, { timeout = 1000 })
open(dismissed)
tools.dismiss(dismissed)
key("q")
settle(0)

-- Pinned notices stay pinned; an explicitly dismissed/recreated ID isn't resumed.
local pinned = tools.notify("pinned", nil, { timeout = 0 })
open(pinned)
key("q")
now = 20000
settle(1)
tools.dismiss()
local same = tools.notify("old", nil, { id = "reused", timeout = 1000 })
open(same)
tools.dismiss(same)
tools.notify("new", nil, { id = same, timeout = 100 })
key("q")
now = 20101
settle(0)

-- Latest means the last created/updated ordinary notice, even after task results.
local older = tools.notify("older", nil, { timeout = 0 })
tools.notify("newer", nil, { timeout = 0 })
tools.notify("last updated", nil, { id = older, timeout = 0 })
tools.progress({ title = "Failure" }):finish("task result", "error")
vim.cmd("NotificationsLatest")
h.wait(function()
  return vim.bo.filetype == "notification-tools-history"
end)
assert(contents():find("last updated", 1, true))
assert(not contents():find("newer", 1, true))
key("q")
tools.show_history({ level = "error" })
h.wait(function()
  return vim.bo.filetype == "notification-tools-history"
end)
key("\r")
h.wait(function()
  return contents():find("task result", 1, true) ~= nil and vim.b.notification_tools_detail == true
end)
key("q")

-- history_size=0 still supports reading a live notice; teardown releases all UI.
tools.setup({ notify = false, history_size = 0, timeout = 100 })
local live = tools.notify("no archive")
local detail = open(live)
vim.api.nvim_buf_delete(0, { force = true })
now = 20202
settle(0)
tools.notify("reset while reading")
open()
tools.setup({ notify = false })
settle(0)
tools.notify("queued")
tools.show_notification()
tools.teardown()
settle(0)
h.eq(nil, vim.api.nvim_get_commands({}).NotificationsLatest)
print(
  "reading: full content, remaining TTL pause/resume, replacements, external close, history selection and teardown passed"
)
