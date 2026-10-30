local h = dofile("tests/helpers.lua")
local tools = require("notification-tools")
local attach, detach = vim.ui_attach, vim.ui_detach
local callbacks, attached, detached = {}, 0, 0
vim.ui_attach = function(ns, opts, callback)
  h.eq({ ext_messages = true }, opts)
  attached = attached + 1
  callbacks[ns] = callback
  vim.o.cmdheight = 0
end
vim.ui_detach = function(ns)
  detached = detached + 1
  callbacks[ns] = nil
end
local function settle()
  vim.wait(40, function()
    return false
  end, 5)
end
local function start(opts)
  tools.setup(
    vim.tbl_deep_extend("force", { timeout = 0, messages = { enabled = true } }, opts or {})
  )
  local handle = assert(tools.attach_messages())
  local callback = callbacks[vim.api.nvim_get_namespaces()["notification-tools.messages"]]
  return handle, callback
end
local function event(callback, kind, message, replace, append, id)
  return callback("msg_show", kind, { { 0, message } }, replace or false, true, append or false, id)
end

-- Defaults and the opt-in alone must never externalize the command line.
vim.o.cmdheight = 2
tools.setup()
h.eq(nil, tools.attach_messages())
assert(not package.loaded["notification-tools.messages"])
tools.setup({ messages = { enabled = true } })
h.eq(0, attached)
h.eq(2, vim.o.cmdheight)
vim.notify("standalone notification")
local task = tools.progress({ title = "standalone progress" })
h.eq(1, #tools.history())
assert(task:is_active())
tools.teardown()
h.eq(2, vim.o.cmdheight)

local lease, callback = start()
assert(lease:is_active())
h.eq(0, vim.o.cmdheight)
assert(not pcall(tools.attach_messages), "only one message owner may attach")
assert(event(callback, "lua_print", "**literal**"))
h.eq(0, #tools.history(), "UI callback must defer model/window work")
settle()
h.eq("**literal**", tools.history()[1].message)
assert(not tools.history()[1].markdown)
h.eq("neovim", tools.history()[1].source)
event(callback, "lua_print", " appended", false, true)
settle()
h.eq(1, #tools.history())
h.eq("**literal** appended", tools.history()[1].message)
event(callback, "lua_print", "replacement", true)
settle()
h.eq(1, #tools.history())
h.eq("replacement", tools.history()[1].message)
event(callback, "emsg", "error")
event(callback, "wmsg", "warning")
settle()
h.eq(vim.log.levels.ERROR, tools.history()[2].level)
h.eq(vim.log.levels.WARN, tools.history()[3].level)

-- Native IDs update the corresponding record even if it is no longer last.
event(callback, "echo", "seven", false, false, 7)
event(callback, "echo", "eight", false, false, 8)
event(callback, "echo", "seven updated", false, false, 7)
event(callback, "echo", " + suffix", false, true)
event(callback, "echo", " + keyed suffix", false, true, 7)
settle()
h.eq(5, #tools.history())
h.eq("eight", tools.history()[4].message)
h.eq("seven updated + suffix + keyed suffix", tools.history()[5].message)
callback("msg_clear")
event(callback, "echo", "new after clear", true, false, 7)
settle()
h.eq(6, #tools.history())

-- Do not claim any interactive or status event, even if a route names it.
for _, kind in ipairs({ "confirm", "confirm_sub", "number_prompt", "return_prompt" }) do
  h.eq(nil, event(callback, kind, "prompt"))
end
local mode = vim.fn.mode
vim.fn.mode = function()
  return "rm"
end
h.eq(nil, event(callback, "", "legacy numbered choice"))
vim.fn.mode = mode
for _, name in ipairs({
  "cmdline_show",
  "cmdline_hide",
  "msg_showcmd",
  "msg_showmode",
  "msg_ruler",
  "popupmenu_show",
}) do
  h.eq(nil, callback(name, {}))
end
settle()
h.eq(6, #tools.history())
lease:detach()
assert(not lease:is_active())
h.eq(2, vim.o.cmdheight)
h.eq(nil, event(callback, "echo", "detached callback"))
local count = detached
lease:detach()
h.eq(count, detached)

-- Source routing composes with the ordinary filter and DND; a history route
-- must stay quiet even if the ordinary filter returns show.
lease, callback = start({
  messages = { routes = { lua_print = "history", echo = "drop" } },
  notification = {
    filter = function()
      return "show"
    end,
  },
})
event(callback, "lua_print", "log only")
event(callback, "echo", "discard")
event(callback, "search_count", "1/2")
event(callback, "bufwrite", "written")
settle()
h.eq(2, #tools.history())
h.eq(0, #h.floats())
tools.set_dnd(true)
event(callback, "wmsg", "quiet warning")
event(callback, "emsg", "visible error")
settle()
h.eq(4, #tools.history())
h.eq(1, #h.floats())

-- :messages presents the native snapshot, including pre-attachment entries,
-- without replaying them as notifications or duplicating the captured store.
callback("msg_history_show", {
  { "echo", { { 0, "older native history" } } },
  { "echomsg", { { 0, " plus suffix" } }, true },
  { "emsg", { { 0, "native error" } } },
})
settle()
h.eq(4, #tools.history())
local lines = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
assert(lines:find("older native history plus suffix", 1, true))
vim.api.nvim_feedkeys("\r", "xt", false)
assert(vim.b.notification_tools_detail)
vim.api.nvim_feedkeys("q", "xt", false)

-- Detach drops queued work; stale handles cannot disconnect a newer instance.
event(callback, "emsg", "must not survive")
lease:detach()
local next_lease, next_callback = start()
lease:detach()
assert(next_lease:is_active())
settle()
h.eq(0, #tools.history())
event(next_callback, "echo", "queued before setup")
tools.setup({ messages = { enabled = true } })
assert(not next_lease:is_active())
settle()
h.eq(0, #tools.history())
h.eq(2, vim.o.cmdheight)

-- Bounded ingress keeps the newest messages and forgets missing append state.
lease, callback = start({ max_pending = 2 })
for i = 1, 5 do
  event(callback, "echo", tostring(i))
end
settle()
h.eq(2, #tools.history())
h.eq("4", tools.history()[1].message)
h.eq("5", tools.history()[2].message)
vim.o.cmdheight = 3
lease:detach()
h.eq(3, vim.o.cmdheight, "do not overwrite a later user option change")

-- Filter diagnostics must not feed back into the failing filter.
lease, callback = start({
  notification = {
    filter = function()
      error("broken native filter")
    end,
  },
})
local err_writeln, reports = vim.api.nvim_err_writeln, 0
vim.api.nvim_err_writeln = function(message)
  reports = reports + 1
  assert(reports < 3, "recursive filter diagnostic")
  h.eq(nil, event(callback, "emsg", message))
end
event(callback, "echo", "filter input")
settle()
h.eq(1, reports)
h.eq(1, #tools.history())
vim.api.nvim_err_writeln = err_writeln
tools.teardown()

-- An attach failure leaves no active lease or queued subscription state.
vim.ui_attach = function()
  error("attach failed")
end
tools.setup({ messages = { enabled = true } })
assert(not pcall(tools.attach_messages))
assert(not require("notification-tools.messages").active())
tools.teardown()
vim.ui_attach, vim.ui_detach = attach, detach
assert(not pcall(tools.setup, { messages = { enabled = "yes" } }))
assert(not pcall(tools.setup, { messages = { routes = { echo = "invalid" } } }))
-- Consumers can join after every complete setup, regardless of loading order.
local ready = 0
local ready_group = vim.api.nvim_create_augroup("NotificationToolsReadyTest", { clear = true })
vim.api.nvim_create_autocmd("User", {
  group = ready_group,
  pattern = "NotificationToolsReady",
  callback = function()
    ready = ready + 1
    vim.notify("Ready consumer")
  end,
})
tools.setup()
h.eq(1, ready)
h.eq("Ready consumer", tools.history()[1].message)
tools.setup({ messages = { enabled = true } })
h.eq(2, ready)
h.eq("Ready consumer", tools.history()[1].message)
tools.teardown()
h.eq(2, ready)
vim.api.nvim_del_augroup_by_id(ready_group)
print(
  "messages: opt-in/provider gating, routing, append/replace, prompts, native history, bounded queue and leases passed"
)
