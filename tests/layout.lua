local h = dofile("tests/helpers.lua")
local tools = require("notification-tools")
local view = require("notification-tools.view")
local model = require("notification-tools.state")
local config = require("notification-tools.config")
h.eq({ "中文", "通知" }, view.wrap("中文通知", 4))
h.eq({ "ab", "cd", "", "e" }, view.wrap("abcd\n\ne", 2))
for _, ambiwidth in ipairs({ "single", "double" }) do
  vim.o.ambiwidth = ambiwidth
  for _, border in ipairs({ "rounded", "none", "double", "solid", "single", "" }) do
    for _, size in ipairs({ { 120, 40 }, { 80, 24 }, { 32, 14 }, { 12, 8 }, { 8, 6 } }) do
      vim.o.columns, vim.o.lines = size[1], size[2]
      vim.o.showtabline = 2
      tools.setup({
        notify = false,
        timeout = 0,
        window = { border = border },
        progress = { stale_timeout = 0 },
      })
      local original_buf = vim.api.nvim_get_current_buf()
      local original_win = vim.api.nvim_get_current_win()
      for i = 1, 8 do
        tools.notify(
          string.rep("中文 🦀 é 很长的信息\n", 12),
          "warn",
          { title = "通知 " .. i }
        )
        tools.progress({ title = "Task " .. i, source = "lua_ls", percentage = 25 })
      end
      vim.wait(35, function()
        return false
      end, 5)
      h.eq(original_buf, vim.api.nvim_get_current_buf())
      h.eq(original_win, vim.api.nvim_get_current_win())
      local boxes = {}
      for _, entry in ipairs(h.floats()) do
        local c = entry.config
        local margin = (not c.border or c.border == "none" or #c.border == 0) and 0 or 2
        assert(c.row >= 1 and c.col >= 0)
        assert(
          c.col + c.width + margin <= vim.o.columns,
          vim.inspect({ config = c, columns = vim.o.columns })
        )
        assert(c.row + c.height + margin <= vim.o.lines - vim.o.cmdheight)
        assert(not c.focusable)
        for _, line in ipairs(entry.lines) do
          assert(vim.fn.strdisplaywidth(line) <= c.width)
        end
        boxes[#boxes + 1] = { c.row, c.row + c.height + margin }
      end
      table.sort(boxes, function(a, b)
        return a[1] < b[1]
      end)
      for i = 2, #boxes do
        assert(boxes[i][1] >= boxes[i - 1][2], "notification and progress windows overlap")
      end
      tools.teardown()
    end
  end
end
vim.o.ambiwidth = "single"

vim.o.columns, vim.o.lines, vim.o.showtabline = 120, 40, 1
tools.setup({ notify = false, timeout = 0 })
tools.notify("Persistent notification")
local task = tools.progress({ title = "Build" })
h.wait(function()
  return #h.floats() == 2
end)
-- Rendering updates reuse windows/buffers, including notification replacement.
local before = {}
for _, entry in ipairs(h.floats()) do
  before[entry.win] = entry.buf
end
task:update({ percentage = 50 })
vim.wait(100, function()
  return false
end, 10)
for _, entry in ipairs(h.floats()) do
  h.eq(before[entry.win], entry.buf)
end
-- Avoid the current tree window without dropping the task.
vim.bo.filetype = "NvimTree"
vim.api.nvim_exec_autocmds("BufEnter", {})
h.wait(function()
  return #h.floats() == 1
end)
vim.bo.filetype = "lua"
vim.api.nvim_exec_autocmds("BufEnter", {})
h.wait(function()
  return #h.floats() == 2
end)
vim.cmd("colorscheme default")
assert(vim.api.nvim_get_hl(0, { name = "NotificationToolsWARN" }).link)
tools.teardown()

-- Expiration is independent of rendering, with pinned notifications retained.
local state = model.new(config.resolve())
state.notices =
  { pinned = { id = "pinned" }, expired = { id = "expired", expires = model.now() - 1 } }
model.expire(state)
assert(state.notices.pinned and not state.notices.expired)
print("layout: Unicode, small screens, borders, non-overlap, focus, reuse and avoid passed")
