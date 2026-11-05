-- Optional shared colors. Never load theme-tools just to display a notification.
local M = {}
local api = vim.api
local palette, stop, changed

function M.definition(name)
  -- Resolve global links without the current window's winhighlight remapping.
  local seen = {}
  while name and not seen[name] do
    seen[name] = true
    local value = api.nvim_get_hl(0, { name = name, link = true, create = false })
    if not value.link then
      return value
    end
    name = value.link
  end
  return {}
end

local function apply(name, value)
  -- Stable public links survive highlight snapshots/restoration. Only their
  -- private targets change, so explicit public overrides remain theme-owned.
  local target = "NotificationToolsDefault" .. name
  api.nvim_set_hl(0, target, value)
  api.nvim_set_hl(0, "NotificationTools" .. name, { default = true, link = target })
end

function M.highlights()
  local groups = {}
  for name, link in pairs({
    Normal = "NormalFloat",
    Border = "FloatBorder",
    Title = "Title",
    MarkdownCode = "String",
    MarkdownLink = "Underlined",
    Meta = "Comment",
    Source = "Comment",
    Cancelled = "Comment",
    NotificationNormal = "NotificationToolsNormal",
    ProgressNormal = "NotificationToolsNormal",
    ERROR = "DiagnosticError",
    WARN = "DiagnosticWarn",
    INFO = "DiagnosticInfo",
    DEBUG = "Comment",
    TRACE = "Comment",
    Progress = "DiagnosticInfo",
    ProgressTrack = "Comment",
    Done = "DiagnosticOk",
  }) do
    groups[name] = { link = link }
  end
  local foreground = M.definition("NormalFloat").fg or M.definition("Normal").fg
  groups.Body, groups.TaskTitle = { fg = foreground }, { fg = foreground }
  if palette then
    local c = palette
    groups.Normal = { fg = c.ui.float_fg, bg = c.ui.float_bg }
    groups.Border = { fg = c.ui.border, bg = c.ui.float_bg }
    groups.Title = { fg = c.ui.accent, bold = true }
    groups.Body, groups.TaskTitle = { fg = c.ui.float_fg }, { fg = c.ui.float_fg }
    groups.MarkdownCode = { fg = c.palette.green }
    groups.MarkdownLink = { fg = c.ui.accent, underline = true }
    for _, name in ipairs({ "Meta", "Source", "Cancelled", "DEBUG", "TRACE", "ProgressTrack" }) do
      groups[name] = { fg = c.ui.muted }
    end
    for name, role in pairs({
      ERROR = "error",
      WARN = "warn",
      INFO = "info",
      Progress = "info",
      Done = "ok",
    }) do
      groups[name] = { fg = c.diagnostic[role] }
    end
  end
  for name, value in pairs(groups) do
    apply(name, value)
  end
end

function M.attach()
  local themes = package.loaded.theme_tools
  if not stop and type(themes) == "table" and type(themes.on_change) == "function" then
    stop = themes.on_change("notification-tools", function(value)
      palette = value
      changed()
    end)
  end
  return stop ~= nil
end

function M.setup(callback)
  changed = callback
  M.attach()
end

function M.teardown()
  if stop then
    stop()
  end
  palette, stop, changed = nil, nil, nil
end

return M
