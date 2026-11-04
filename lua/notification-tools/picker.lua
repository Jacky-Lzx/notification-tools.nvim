-- Optional selection-tools consumer; notification capture never loads this module.
local M = {}
local active
local names = { [0] = "TRACE", "DEBUG", "INFO", "WARN", "ERROR", "OFF" }

local function heading(item)
  local source = item.source and item.source ~= item.title and (" [" .. item.source .. "]") or ""
  return os.date("%H:%M:%S", item.time)
    .. "  "
    .. names[item.level]
    .. "  "
    .. item.title
    .. source
    .. ((item.count or 1) > 1 and (" ×" .. item.count) or "")
end

function M.close()
  local picker = active
  active = nil
  if picker and not picker.closed then
    picker:close()
  end
end

function M.open(records, on_choice)
  local ok, selection = pcall(require, "selection_tools")
  assert(ok, "NotificationsPick requires selection-tools.nvim")
  M.close()
  local view = package.loaded["notification-tools.view"]
  if view then
    view.close_history()
  end
  local items = {}
  for index = #records, 1, -1 do
    items[#items + 1] = records[index]
  end
  local picker = selection.open({
    prompt = "Notifications",
    kind = "notification-tools-history",
    items = items,
    resume = false, -- Callbacks belong to this notification-tools instance.
    multi = false,
    format_item = function(item)
      return heading(item) .. "  " .. item.message .. "  " .. (item.details or "")
    end,
    preview = { enabled = true, highlight_line = false, highlight_matches = false },
    previewer = function(ctx)
      local item = ctx.item
      local lines = { heading(item), "" }
      vim.list_extend(lines, vim.split(item.message, "\n", { plain = true }))
      if item.details and item.details ~= "" then
        lines[#lines + 1] = ""
        vim.list_extend(lines, vim.split(item.details, "\n", { plain = true }))
      end
      ctx.set_lines(lines, item.markdown and "markdown" or "text", item.title)
    end,
    on_close = function(closed)
      if active == closed then
        active = nil
      end
    end,
    on_choice = on_choice,
  })
  active = picker
  return picker
end

return M
