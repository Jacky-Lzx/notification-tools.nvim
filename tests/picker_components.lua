vim.opt.rtp:prepend(vim.fn.getcwd())
vim.opt.rtp:append(vim.fn.getcwd() .. "/../selection-tools.nvim")
vim.o.columns, vim.o.lines = 220, 60
local api = vim.api
local selection = require("selection_tools")
selection.setup({
  layout = { width = 0.95 },
  select = { layout = { width = 0.95, min_width = 200, max_width = 220 } },
  matcher = { backend = "native" },
  component_defaults = { path = { hl = "Special" }, time = { hl = "String" } },
})
local function ready(p)
  assert(
    vim.wait(5000, function()
      return not p.loading and not p.matching
    end, 5),
    "picker did not settle"
  )
  assert(not p.error, p.error)
end
local function spans(p, group)
  local result = {}
  for _, mark in ipairs(api.nvim_buf_get_extmarks(p.list_buf, -1, 0, -1, { details = true })) do
    if mark[4].hl_group == group then
      local line = api.nvim_buf_get_lines(p.list_buf, mark[2], mark[2] + 1, false)[1]
      result[#result + 1] = line:sub(mark[3] + 1, mark[4].end_col)
    end
  end
  return table.concat(result)
end
local tools = require("notification-tools")
tools.setup({ notify = false, timeout = 0 })
tools.notify(
  "first 中文🙂 needle",
  "warn",
  { title = "Build", source = "compiler", details = "full detail" }
)
tools.notify("second", "error", { title = "Server", source = "lua_ls" })
local p = tools.pick_history()
ready(p)
local item = p.entries[2].item
assert(spans(p, "String"):find(os.date("%H:%M:%S", item.time), 1, true))
assert(spans(p, "NotificationToolsWARN") == "WARN")
assert(spans(p, "NotificationToolsTitle"):find("Build", 1, true))
assert(spans(p, "NotificationToolsSource"):find(" [compiler]", 1, true))
p:set_query("needle")
assert(#p.matches == 1 and p:current().message == "first 中文🙂 needle")
assert(spans(p, "SelectionToolsMatch") == "needle")
local time, count = os.date("%H:%M:%S", item.time), 0
for _, entry in ipairs(p.entries) do
  if os.date("%H:%M:%S", entry.item.time) == time then
    count = count + 1
  end
end
p:set_query(time)
assert(#p.matches == count)
p:set_query("full detail")
assert(#p.matches == 1)
p:close()
assert(#tools.history() == 2 and #api.nvim_list_wins() == 1)
-- Long messages must not consume the title at ordinary terminal widths.
selection.setup({ layout = { width = 0.8 }, matcher = { backend = "native" } })
vim.o.columns, vim.o.lines = 120, 36
tools.clear_history()
tools.notify(
  "narrow-match " .. string.rep("long body ", 80),
  "warn",
  { title = "Compiler warning", source = "compiler" }
)
local narrow = tools.pick_history()
ready(narrow)
assert(spans(narrow, "NotificationToolsTitle"):find("Compiler warning", 1, true))
narrow:set_query("narrow-match")
assert(#narrow.matches == 1 and narrow:current().title == "Compiler warning")
assert(spans(narrow, "NotificationToolsTitle"):find("Compiler warning", 1, true))
narrow:close()
tools.teardown()
print(
  "Notification components: shared time style, semantic colors, Unicode, metadata search and cancellation passed"
)
