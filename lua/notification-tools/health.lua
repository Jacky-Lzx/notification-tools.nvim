local M = {}

function M.check()
  vim.health.start("notification-tools.nvim")
  if vim.fn.has("nvim-0.10") == 0 then
    vim.health.error("Neovim 0.10+ is required", { "Upgrade Neovim" })
    return
  end
  local issues = {}
  local function problem(level, message, advice)
    issues[#issues + 1] = { level = level, message = message, advice = advice }
  end
  local plugin = package.loaded["notification-tools"]
  local status = plugin and plugin.status()
  if not status or not status.configured then
    vim.health.info("Not active; notification ownership checks skipped.")
    return
  end
  if status.config.notify and not status.owns_notify then
    problem(
      "warn",
      "vim.notify was replaced; notifications no longer use this renderer.",
      { "Restore the intended notification owner or disable notify in notification-tools" }
    )
  end
  local messages = package.loaded["notification-tools.messages"]
  local noice = package.loaded["noice.config"]
  local opts = noice and noice.options
  if messages and messages.active() and opts and (opts.messages or {}).enabled then
    problem(
      "warn",
      "Noice messages are enabled; native message consumers conflict.",
      { "Disable Noice messages while notification-tools owns native messages" }
    )
  end

  table.sort(issues, function(a, b)
    if a.level ~= b.level then
      return a.level == "error"
    end
    return a.message < b.message
  end)
  for _, issue in ipairs(issues) do
    vim.health[issue.level](issue.message, issue.advice)
  end
  if #issues == 0 then
    vim.health.ok("Notification runtime requirements are satisfied.")
  end
  vim.health.info("Details: :NotificationToolsInfo")
end

return M
