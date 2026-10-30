local h = dofile("tests/helpers.lua")
local tools = require("notification-tools")
tools.setup({ notify = false, lsp = { ignore = { "ignored" } } })
local original = vim.lsp.get_client_by_id
local clients = {
  [1] = {
    name = "lua_ls",
    attached_buffers = { [1] = true },
    is_stopped = function()
      return false
    end,
  },
  [2] = {
    name = "texquill",
    attached_buffers = { [1] = true },
    is_stopped = function()
      return false
    end,
  },
  [3] = { name = "ignored" },
}
vim.lsp.get_client_by_id = function(id)
  return clients[id]
end
local function progress(client, token, kind, value)
  value = vim.tbl_extend("force", { kind = kind }, value or {})
  vim.api.nvim_exec_autocmds("LspProgress", {
    data = { client_id = client, params = { token = token, value = value } },
  })
end
progress(1, 1, "begin", { title = "Index" })
progress(1, "1", "begin", { title = "Check" })
progress(2, 1, "begin", { title = "Build" })
progress(3, 1, "begin", { title = "Ignore" })
progress(99, 1, "begin")
progress(1, "partial", "not-workdone", { answer = 42 })
h.eq(3, #tools.tasks())
progress(1, 1, "report", { percentage = 42, message = "Checking" })
local found
for _, task in ipairs(tools.tasks()) do
  if task.id == "lsp:1:number:1" then
    found = task
  end
end
h.eq("Index", found.title)
h.eq(42, found.percentage)
progress(1, 1, "end", { message = "Indexed" })
progress(1, 1, "begin", { title = "Reindex" })
h.eq(3, #tools.tasks())
progress(2, "late", "report", { message = "Late setup" })
h.eq(4, #tools.tasks())
progress(2, "unknown", "end")
h.eq(4, #tools.tasks())

vim.api.nvim_exec_autocmds("LspDetach", { data = { client_id = 1 } })
vim.wait(30, function()
  return false
end, 10)
for _, task in ipairs(tools.tasks()) do
  if task.source == "lua_ls" then
    assert(not task.done, "detaching one buffer must not cancel a live client")
  end
end
clients[1] = nil
vim.api.nvim_exec_autocmds("LspDetach", { data = { client_id = 1 } })
h.wait(function()
  for _, task in ipairs(tools.tasks()) do
    if task.source == "lua_ls" and not task.done then
      return false
    end
  end
  return true
end)

-- A queued detach from the old instance must not cancel tasks in the new one.
vim.api.nvim_exec_autocmds("LspDetach", { data = { client_id = 2 } })
tools.setup({ notify = false })
progress(2, 1, "begin", { title = "New" })
vim.wait(30, function()
  return false
end, 10)
h.eq(false, not not tools.tasks()[1].done)
tools.setup({ notify = false, lsp = { enabled = false } })
progress(2, 1, "begin")
h.eq({}, tools.tasks())
-- External consumers own their events and use only the generic public API.
tools.progress({ id = "consumer:one", title = "First request", source = "external" }):cancel()
tools
  .progress({ id = "consumer:two", title = "Second request", source = "external" })
  :finish(nil, "error")
h.eq("error", tools.tasks()[1].status)
h.eq("cancelled", tools.tasks()[2].status)
for _, autocmd in ipairs(vim.api.nvim_get_autocmds({ group = "NotificationTools" })) do
  assert(autocmd.event ~= "User", "the plugin must not subscribe to consumer-specific events")
end
vim.lsp.get_client_by_id = original
tools.teardown()
print("integrations: concurrent LSP tokens, detach, disabled hooks and generic consumers passed")
