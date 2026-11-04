local h = dofile("tests/helpers.lua")
local tools = require("notification-tools")
tools.setup({ notify = false, timeout = 0 })
assert(not package.loaded["notification-tools.picker"])
assert(not package.loaded.selection_tools)
local a = tools.notify(
  "first\n中文🙂",
  "warn",
  { title = "Build", source = "compiler", details = "full detail" }
)
local b = tools.notify("second", "error", { title = "Server", source = "lua_ls" })
tools.progress({ title = "Task", source = "compiler" }):finish("failed task", "error")
package.preload.selection_tools = function()
  error("optional backend is not installed")
end
local available, err = pcall(tools.pick_history)
assert(not available and tostring(err):find("requires selection-tools.nvim", 1, true))
h.eq(3, #tools.history())
package.loaded.selection_tools = nil -- LuaJIT retains a sentinel after a loader error.

-- Exercise the optional backend contract without requiring it for core users/CI.
local spec
package.preload.selection_tools = function()
  return {
    open = function(opts)
      spec = opts
      return {
        closed = false,
        close = function(self)
          self.closed = true
          opts.on_close(self)
          opts.on_choice(nil)
        end,
      }
    end,
  }
end
local picker = tools.pick_history({ source = "compiler", level = "warn" })
h.eq(2, #spec.items)
h.eq("failed task", spec.items[1].message)
h.eq(a, spec.items[2].id)
assert(spec.format_item(spec.items[2]):find("first\n中文🙂  full detail", 1, true))
local preview
spec.previewer({
  item = spec.items[2],
  set_lines = function(lines)
    preview = table.concat(lines, "\n")
  end,
})
assert(preview:find("first\n中文🙂\n\nfull detail", 1, true))
-- A cancelled picker must not open a reader or change history.
picker:close()
h.eq(3, #tools.history())
assert(not package.loaded["notification-tools.history"])

vim.cmd("NotificationsPick level=error source=lua_ls title=server")
h.eq(1, #spec.items)
h.eq(b, spec.items[1].id)
assert(not pcall(vim.cmd, "NotificationsPick unknown=x"))
-- Records evicted while searching still open in full, without resurrecting a popup.
local choice, item = spec.on_choice, spec.items[1]
tools.dismiss()
tools.clear_history()
choice(item)
h.wait(function()
  return vim.b.notification_tools_detail == true
end)
assert(table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n"):find("second", 1, true))
vim.api.nvim_feedkeys("q", "xt", false)
h.eq({}, tools.history())

-- Instance replacement closes the old picker and invalidates saved callbacks.
tools.notify("old instance")
local old = tools.pick_history()
local stale, old_item = spec.on_choice, spec.items[1]
tools.setup({ notify = false })
assert(old.closed)
stale(old_item)
vim.wait(40)
assert(vim.bo.filetype ~= "notification-tools-history")
local empty = tools.pick_history()
h.eq({}, spec.items)
tools.teardown()
assert(empty.closed)
h.eq(nil, vim.api.nvim_get_commands({}).NotificationsPick)
print(
  "picker: optional loading, filtered snapshots, full preview, cancellation, eviction and stale callbacks passed"
)
