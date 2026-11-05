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
assert(vim.api.nvim_get_hl(0, { name = "NotificationToolsINFO", link = true }).link)
vim.api.nvim_set_hl(0, "DiagnosticInfo", { fg = 0x123456 })
vim.api.nvim_set_hl(0, "NormalFloat", { fg = 0x654321 })
vim.api.nvim_exec_autocmds("ColorScheme", { pattern = "picker" })
h.wait(function()
  local theme = require("notification-tools.theme")
  return theme.definition("NotificationToolsINFO").fg == 0x123456
    and theme.definition("NotificationToolsBody").fg == 0x654321
end)
h.eq(2, #spec.items)
h.eq("failed task", spec.items[1].message)
h.eq(a, spec.items[2].id)
assert(
  spec.format_item(spec.items[2]):find("first ↵ 中文🙂 · full detail [compiler]", 1, true)
)
assert(not spec.item_icons and spec.result_layout == "plain")
local content_column
for _, item in ipairs(spec.items) do
  local label = spec.format_item(item)
  local parts = vim.split(label, " │ ", { plain = true })
  h.eq(4, #parts)
  h.eq(8, vim.fn.strdisplaywidth(parts[1]))
  h.eq(5, vim.fn.strdisplaywidth(parts[2]))
  local column = vim.fn.strdisplaywidth(table.concat({ parts[1], parts[2], parts[3] }, " │ "))
  content_column = content_column or column
  h.eq(content_column, column)
  local groups = {}
  for _, range in ipairs(spec.highlight_item(item)) do
    assert(range[1] >= 0 and range[2] <= #label and range[1] < range[2])
    assert(range.priority < 110, "semantic colors must allow fuzzy matches to stand out")
    groups[range.hl] = label:sub(range[1] + 1, range[2])
  end
  h.eq(item.title, groups.NotificationToolsTitle)
  local level = item.level == vim.log.levels.ERROR and "ERROR" or "WARN"
  h.eq(level, groups["NotificationTools" .. level])
end
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

-- Title padding uses terminal cells, including wide and combining characters.
tools.notify("unicode body", "info", { title = "中文🙂é\tTitle", source = "unicode" })
tools.pick_history()
local title_cells
for _, item in ipairs(spec.items) do
  local parts = vim.split(spec.format_item(item), " │ ", { plain = true })
  local cells = vim.fn.strdisplaywidth(parts[3])
  title_cells = title_cells or cells
  h.eq(title_cells, cells)
end
h.eq(
  "中文🙂é  Title",
  vim.trim(vim.split(spec.format_item(spec.items[1]), " │ ", { plain = true })[3])
)
h.eq("中文🙂é\tTitle", tools.history()[#tools.history()].title)

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
  "picker: aligned Unicode columns, semantic highlights, full search/preview, cancellation, eviction and stale callbacks passed"
)
