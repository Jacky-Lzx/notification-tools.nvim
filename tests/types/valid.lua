local tools = require("notification-tools")
---@type notification_tools.Config
local opts = {
  notify = true,
  window = { padding = { horizontal = 2 } },
  progress = { style = "bar", history = "errors", spinner = { "." } },
  notification = {
    dnd_level = "ERROR",
    filter = function(notice)
      local source = notice.source:lower()
      return source == "background" and "history" or nil
    end,
  },
  lsp = { ignore = { "ignored" } },
}
---@type notification_tools.API
local api = tools.setup(opts)
local id = api.notify({ "message" }, "Warn", { title = "Build", timeout = 0 })
api.notify("updated", 3, { replace = id and { id = id } or nil, markdown = false })
local task = api.progress({ id = "consumer:one", percentage = 0, history = false })
---@type notification_tools.TaskHandle
local updated = task:update({ percentage = 65, message = "Working", history = "all" })
updated:finish("Done", "success")
task:cancel()
---@type boolean
local active = task:is_active()
---@type notification_tools.Record[]
local history = api.history({ level = "warning", source = "Build", title = "build" })
---@type notification_tools.TaskSnapshot[]
local tasks = api.tasks()
api.show_history({ level = 3 })
api.show_notification(id)
api.dismiss(id)
api.set_dnd(true)
api.toggle_dnd()
api.is_dnd()
api.clear_tasks()
api.clear_history()
api.teardown()
return { history = history, tasks = tasks, active = active, id = updated.id }
