local h = dofile("tests/helpers.lua")
local tools = require("notification-tools")
tools.setup({ notify = false, timeout = 0, level = "trace" })
local a = tools.notify("one\n**two**", "info", { title = "Build", source = "compiler" })
local b = tools.notify("warning", "warn", { title = "Build warnings", source = "compiler" })
tools.notify("failed", "error", { title = "Language server", source = "lua_ls" })
h.eq(2, #tools.history({ level = "warn" }))
h.eq(2, #tools.history({ source = "compiler", title = "BUILD" }))
h.eq(1, #tools.history({ level = "warn", source = "compiler" }))
h.eq(0, #tools.history({ level = "off" }))
assert(not pcall(tools.show_history, { source = 123 }))
local filtered = tools.history({ level = "error" })
filtered[1].message = "changed"
h.eq("failed", tools.history({ level = "error" })[1].message)

tools.show_history()
h.wait(function()
  return vim.bo.filetype == "notification-tools-history"
end)
local win, buf = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
local function lines()
  return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
end
local function key(keys)
  vim.api.nvim_feedkeys(keys, "xt", false)
end
local function text()
  return table.concat(lines(), "\n")
end
key("]n")
h.eq(5, vim.api.nvim_win_get_cursor(win)[1])
key("]n")
h.eq(8, vim.api.nvim_win_get_cursor(win)[1])
key("[n")
h.eq(5, vim.api.nvim_win_get_cursor(win)[1])
vim.api.nvim_win_set_cursor(win, { 6, 3 }) -- body of b
-- Updating an earlier notice reorders history. Preserve b and its row/column offset.
tools.notify("updated first", nil, { id = a })
tools.notify("new entry", "error", { title = "Later" })
assert(not text():find("new entry", 1, true), "history is refreshed explicitly")
key("r")
h.eq(buf, vim.api.nvim_get_current_buf())
h.eq(win, vim.api.nvim_get_current_win())
h.eq({ 2, 3 }, vim.api.nvim_win_get_cursor(win))
assert(text():find("new entry", 1, true))
assert(text():find("[compiler]", 1, true))
assert(not vim.bo[buf].modifiable)
local select, input = vim.ui.select, vim.ui.input
vim.ui.select = function(items, _, callback)
  callback("WARN")
end
key("gl")
assert(not text():find("updated first", 1, true))
assert(text():find("warning", 1, true))
vim.ui.select = function(items, _, callback)
  h.eq(false, items[1])
  callback("compiler")
end
key("gs")
assert(text():find("warning", 1, true))
assert(not text():find("failed", 1, true))
vim.ui.input = function(_, callback)
  callback("absent")
end
key("gt")
h.eq({ "No notifications" }, lines())
key("R")
assert(text():find("updated first", 1, true))
assert(text():find("warning", 1, true))
-- Cancelled prompts keep the current filter and delayed old callbacks are inert.
vim.ui.input = function(_, callback)
  callback(nil)
end
local before = lines()
key("gt")
h.eq(before, lines())
local delayed
vim.ui.select = function(_, _, callback)
  delayed = callback
end
key("gl")
key("q")
assert(not vim.api.nvim_buf_is_valid(buf))
vim.cmd("Notifications level=error source=lua_ls")
h.wait(function()
  return vim.bo.filetype == "notification-tools-history"
end)
local next_buf = vim.api.nvim_get_current_buf()
delayed("INFO")
h.eq(next_buf, vim.api.nvim_get_current_buf())
local current = table.concat(vim.api.nvim_buf_get_lines(next_buf, 0, -1, false), "\n")
assert(current:find("failed", 1, true) and not current:find("warning", 1, true))
assert(not pcall(vim.cmd, "Notifications unknown=x"))
vim.ui.select, vim.ui.input = select, input
tools.clear_history()
key("r")
h.eq({ "No notifications" }, vim.api.nvim_buf_get_lines(next_buf, 0, -1, false))
tools.teardown()
print(
  "browsing: severity/source/title filters, native navigation, anchored refresh and stale prompt cleanup passed"
)
