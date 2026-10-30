local h = dofile("tests/helpers.lua")
vim.opt.runtimepath:append(assert(vim.env.NOTIFICATION_TOOLS_LAZY_ROOT))
local original = vim.notify
vim.o.loadplugins = true -- The runner uses --noplugin for isolation.
local spec = dofile("examples/lazy.lua")
spec[1].dir = vim.fn.getcwd()
require("lazy").setup({
  spec = spec,
  lockfile = vim.fn.stdpath("state") .. "/notification-tools-lock.json",
  install = { missing = false },
  checker = { enabled = false },
  change_detection = { enabled = false },
  pkg = { enabled = false },
  performance = { rtp = { reset = false } },
})
assert(package.loaded["notification-tools"], "lazy.nvim did not resolve the plugin main module")
assert(vim.notify ~= original)
h.eq(2, vim.fn.exists(":Notifications"))
vim.notify("Loaded through lazy.nvim", "info")
h.eq("Loaded through lazy.nvim", require("notification-tools").history()[1].message)
require("notification-tools").teardown()
print("lazy: real lazy.nvim local spec, setup and vim.notify ownership passed")
