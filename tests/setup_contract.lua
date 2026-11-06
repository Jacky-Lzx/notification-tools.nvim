vim.opt.rtp:prepend(vim.fn.getcwd())
local plugin = require("notification-tools")
local options = { notify = false, lsp = { enabled = false }, messages = { enabled = false } }
local caller = vim.deepcopy(options)
plugin.setup(options)
assert(vim.deep_equal(caller, options), "setup mutated caller configuration")
local commands = vim.api.nvim_get_commands({})
local handlers = vim.api.nvim_get_autocmds({})
assert(not pcall(plugin.setup, false), "setup(false) must reject an invalid configuration type")
assert(vim.deep_equal(commands, vim.api.nvim_get_commands({})), "Invalid setup replaced commands")
assert(vim.deep_equal(handlers, vim.api.nvim_get_autocmds({})), "Invalid setup replaced handlers")
plugin.setup(caller)
assert(#vim.api.nvim_get_autocmds({}) == #handlers, "Repeated setup duplicated automatic handlers")
print(
  "notification-tools.nvim: setup input isolation, invalid configuration and registration lifetime passed"
)

local notify = vim.notify
assert(not pcall(plugin.setup, { progress = { interval = -1 } }))
assert(vim.notify == notify)
plugin.dispose()
plugin.dispose()
assert(vim.fn.exists("#NotificationTools") == 0)
assert(vim.notify == notify)
plugin.setup(caller)
plugin.dispose()
