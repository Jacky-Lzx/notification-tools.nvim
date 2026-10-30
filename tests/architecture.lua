local h = dofile("tests/helpers.lua")
local tools = require("notification-tools")
local markdown = require("notification-tools.markdown")
tools.setup({ notify = false, timeout = 0 })
assert(not package.loaded["notification-tools.history"])
local id = tools.notify("**First body**", "info", { title = "Build", details = "_detail_" })
tools.notify("Warning body", "warn", { title = "Server" })
local snapshot = tools.history({ level = "warn" })
h.eq(1, #snapshot)
snapshot[1].message = "must not mutate stored records"
h.eq("Warning body", tools.history({ level = "warn" })[1].message)
assert(
  not package.loaded["notification-tools.history"],
  "snapshot filtering must not load the history UI"
)

local source, parses = markdown.source, 0
markdown.source = function(...)
  parses = parses + 1
  return source(...)
end
tools.show_history()
h.wait(function()
  return vim.bo.filetype == "notification-tools-history"
end)
local before = parses
local buf, ns = vim.api.nvim_get_current_buf(), vim.api.nvim_create_namespace("notification-tools")
local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
local function key(keys)
  vim.api.nvim_feedkeys(keys, "xt", false)
end
key("r")
h.eq(before, parses)
h.eq(marks, vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true }))
-- Metadata-only changes reuse the body/source spans, and new bodies invalidate them.
tools.notify("**First body**", "info", { title = "Build", details = "_detail_" })
key("r")
h.eq(before, parses)
assert(table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n"):find("×2", 1, true))
local select = vim.ui.select
vim.ui.select = function(_, _, callback)
  callback("WARN")
end
key("gl")
key("R")
h.eq(before, parses)
vim.ui.select = select
tools.notify("**Replacement body**", nil, { id = id })
key("r")
assert(parses > before)
markdown.source = source
key("q")
-- Teardown must not delete a command installed by a subsequent owner.
vim.api.nvim_create_user_command("Notifications", function() end, { force = true })
local replacement = vim.api.nvim_get_commands({}).Notifications.definition
tools.teardown()
h.eq(replacement, vim.api.nvim_get_commands({}).Notifications.definition)
vim.api.nvim_del_user_command("Notifications")
-- A filter that replaces the plugin instance cannot insert into its new store.
tools.setup({
  notify = false,
  notification = {
    filter = function()
      tools.setup({ notify = false })
      return "show"
    end,
  },
})
h.eq(nil, tools.notify("old instance"))
h.eq({}, tools.history())
tools.teardown()
-- Retaining an inert task handle must not retain the entire previous store.
local model = require("notification-tools.state")
local create, weak = model.new, setmetatable({}, { __mode = "v" })
model.new = function(config)
  local value = create(config)
  weak[1] = value
  return value
end
tools.setup({ notify = false })
model.new = create
local old_handle = tools.progress({ title = "Retained by producer" })
tools.teardown()
collectgarbage("collect")
collectgarbage("collect")
h.eq(nil, weak[1])
assert(not old_handle:is_active())
print(
  "architecture: pure snapshots, cached history bodies/spans, command ownership, instance isolation and store release passed"
)
