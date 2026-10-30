local h = dofile("tests/helpers.lua")
local tools = require("notification-tools")
local original = vim.notify
local function cold()
  for _, module in ipairs({ "view", "layout", "markdown", "text", "history" }) do
    assert(
      not package.loaded["notification-tools." .. module],
      "unexpected eager module: " .. module
    )
  end
end
local function settle()
  vim.wait(80, function()
    return false
  end, 5)
end
cold()
tools.setup({ timeout = 0 })
assert(vim.notify ~= original)
h.eq(2, vim.fn.exists(":Notifications"))
for _, event in ipairs({ "UIEnter", "BufEnter", "WinEnter", "VimResized", "TabEnter" }) do
  vim.api.nvim_exec_autocmds(event, {})
end
vim.api.nvim_exec_autocmds("OptionSet", { pattern = "ambiwidth" })
vim.cmd.colorscheme("evening")
settle()
cold()
h.eq(nil, vim.notify("Below minimum", "debug"))
h.eq({}, tools.history())
cold()
-- Startup notifications are captured synchronously even while presentation sleeps.
tools.set_dnd(true)
local startup_id = vim.notify("Startup record", "info", { timeout = 20 })
h.eq(startup_id, tools.history()[1].id)
settle()
cold()
tools.teardown()
h.eq(original, vim.notify)
cold()

tools.setup({
  notification = {
    filter = function(notice)
      return notice.source == "drop" and "drop" or "history"
    end,
  },
})
vim.notify("Log only", "info")
h.eq(nil, tools.notify("Discard", "info", { source = "drop" }))
settle()
cold()
-- The LSP listener must already exist before any rendering module is loaded.
tools.setup({ progress = { enabled = false } })
local client = vim.lsp.get_client_by_id
vim.lsp.get_client_by_id = function(id)
  return id == 10 and { name = "early-lsp" } or client(id)
end
vim.api.nvim_exec_autocmds("LspProgress", {
  data = {
    client_id = 10,
    params = {
      token = "startup",
      value = { kind = "begin", title = "Early indexing", percentage = 10 },
    },
  },
})
h.eq("Early indexing", tools.tasks()[1].title)
settle()
cold()
vim.lsp.get_client_by_id = client
-- Avoided panels do not cause display imports either.
tools.setup({ notify = false })
vim.bo.filetype = "NvimTree"
tools.progress({ title = "Hidden task" })
settle()
cold()
vim.bo.filetype = "lua"
vim.api.nvim_exec_autocmds("BufEnter", {})
h.wait(function()
  return #h.floats() == 1
end)
assert(package.loaded["notification-tools.view"] and package.loaded["notification-tools.layout"])
assert(
  not package.loaded["notification-tools.markdown"],
  "plain task progress must not load Markdown"
)
tools.teardown()
-- A reconfigured instance initializes highlights on its first actual display.
vim.cmd.colorscheme("morning")
tools.setup({ notify = false, timeout = 0 })
tools.notify("**First visible notice**")
h.wait(function()
  return #h.floats() == 1
end)
assert(vim.api.nvim_get_hl(0, { name = "NotificationToolsBodyMarkdownBold", link = false }).bold)
tools.teardown()
print(
  "startup lazy: early notify/LSP capture, cold empty/filtered/hidden paths, first display and reconfiguration passed"
)
