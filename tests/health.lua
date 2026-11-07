vim.opt.rtp:prepend(vim.fn.getcwd())
local reports = {}
for _, level in ipairs({ "start", "ok", "warn", "info", "error" }) do
  vim.health[level] = function(message)
    reports[#reports + 1] = { level, message }
  end
end
local health = require("notification-tools.health")
health.check()
assert(not package.loaded["notification-tools"], "Health must not initialize an unused renderer")
assert(#reports == 2 and reports[2][1] == "info")
package.loaded["notification-tools"] = {
  status = function()
    return { configured = true, config = { notify = true }, owns_notify = false }
  end,
}
reports = {}
health.check()
assert(
  reports[2][1] == "warn" and reports[2][2]:find("vim.notify was replaced", 1, true),
  vim.inspect(reports)
)
for _, row in ipairs(reports) do
  assert(row[1] ~= "ok", "A broken renderer must not report all-clear")
end
print("notification-tools.nvim: inactive inspection and actual renderer failure reporting passed")
