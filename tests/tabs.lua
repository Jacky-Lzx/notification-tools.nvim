local h = dofile("tests/helpers.lua")
local tools = require("notification-tools")
local model = require("notification-tools.state")
local now = 1000
model.now = function()
  return now
end
vim.o.columns, vim.o.lines = 120, 40
tools.setup({ notify = false, timeout = 1000, progress = { stale_timeout = 0 } })
local id = tools.notify("Follow the active tab")
local task = tools.progress({ title = "Build", percentage = 20 })
h.wait(function()
  return #h.floats() == 2
end)
local original = vim.api.nvim_get_current_tabpage()
for _ = 1, 3 do
  vim.cmd.tabnew()
  local tab, win = vim.api.nvim_get_current_tabpage(), vim.api.nvim_get_current_win()
  h.wait(function()
    local floats = h.floats()
    if #floats ~= 2 then
      return false
    end
    for _, entry in ipairs(floats) do
      if vim.api.nvim_win_get_tabpage(entry.win) ~= tab then
        return false
      end
    end
    return true
  end)
  h.eq(win, vim.api.nvim_get_current_win())
  task:update({ percentage = 50 })
end
-- A reader in a tab we leave must not retain an invisible timeout pause.
tools.show_notification(id)
h.wait(function()
  return vim.b.notification_tools_detail == true
end)
local reader = vim.api.nvim_get_current_win()
now = 1500
vim.api.nvim_set_current_tabpage(original)
h.wait(function()
  return not vim.api.nvim_win_is_valid(reader)
end)
now = 2499
vim.api.nvim_exec_autocmds("VimResized", {})
vim.wait(50, function()
  return false
end, 5)
h.eq(2, #h.floats())
now = 2501
vim.api.nvim_exec_autocmds("VimResized", {})
h.wait(function()
  return #h.floats() == 1
end)
assert(task:is_active())
tools.teardown()
h.eq(0, #h.floats())
print("tabs: global notices/tasks follow the active tab, preserve focus and release hidden readers")
