local M = {}
local owned = {}
local function create(name, callback, opts)
  vim.api.nvim_create_user_command(name, callback, opts)
  owned[name] = vim.api.nvim_get_commands({})[name].definition
end

function M.clear()
  local current = vim.api.nvim_get_commands({})
  for name, definition in pairs(owned) do
    if current[name] and current[name].definition == definition then
      vim.api.nvim_del_user_command(name)
    end
  end
  owned = {}
end

function M.setup(tools)
  create("Notifications", function(args)
    local opts = {}
    for _, arg in ipairs(args.fargs) do
      local key, value = arg:match("^(%a+)=(.+)$")
      assert(
        key == "level" or key == "source" or key == "title",
        "expected level=, source= or title="
      )
      opts[key] = value
    end
    tools.show_history(opts)
  end, {
    desc = "Notification history",
    force = true,
    nargs = "*",
    complete = function()
      return { "level=", "source=", "title=" }
    end,
  })
  create("NotificationsDismiss", function()
    tools.dismiss()
  end, { desc = "Dismiss visible notifications", force = true })
  create(
    "NotificationsClear",
    tools.clear_history,
    { desc = "Clear notification history", force = true }
  )
  create("NotificationsLatest", function()
    if not tools.show_notification() then
      vim.api.nvim_echo({ { "No notifications" } }, false, {})
    end
  end, { desc = "Read the latest notification", force = true })
  create("NotificationsDnd", function(args)
    local value = args.args
    assert(
      value == "" or vim.tbl_contains({ "on", "off", "toggle" }, value),
      "expected on, off or toggle"
    )
    local enabled
    if value == "on" or value == "off" then
      enabled = tools.set_dnd(value == "on")
    else
      enabled = tools.toggle_dnd()
    end
    vim.api.nvim_echo({ { "Notifications DND: " .. (enabled and "on" or "off") } }, false, {})
  end, {
    nargs = "?",
    force = true,
    desc = "Toggle notification do not disturb",
    complete = function()
      return { "on", "off", "toggle" }
    end,
  })
  create(
    "NotificationToolsDemo",
    tools.demo,
    { desc = "Preview notifications and tasks", force = true }
  )
end

return M
