-- Optional selection-tools consumer; notification capture never loads this module.
local M = {}
local active
local names = { [0] = "TRACE", "DEBUG", "INFO", "WARN", "ERROR", "OFF" }

local function single_line(value)
  return tostring(value):gsub("\r", "\\r"):gsub("\n", " ↵ "):gsub("\t", "  "):gsub("%z", "\\0")
end

-- Build labels once for this snapshot. Measure display cells for alignment, but
-- keep byte offsets for selection-tools' semantic and fuzzy-match highlights.
local function columns(items)
  local titles, title_width = {}, 0
  for _, item in ipairs(items) do
    local title = single_line(item.title) .. ((item.count or 1) > 1 and (" ×" .. item.count) or "")
    titles[item] = title
    title_width = math.max(title_width, vim.fn.strdisplaywidth(title))
  end
  local rows = {}
  for _, item in ipairs(items) do
    local label, highlights = "", {}
    local function append(value, group, width)
      local start = #label
      label = label .. value
      if #value > 0 then
        highlights[#highlights + 1] = { start, #label, hl = group, priority = 100 }
      end
      if width then
        label = label .. string.rep(" ", math.max(0, width - vim.fn.strdisplaywidth(value)))
      end
    end
    local function separator()
      append(" │ ", "NotificationToolsMeta")
    end
    append(os.date("%H:%M:%S", item.time), "NotificationToolsMeta")
    separator()
    local level = names[item.level]
    append(level, level == "OFF" and "NotificationToolsMeta" or ("NotificationTools" .. level), 5)
    separator()
    append(titles[item], "NotificationToolsTitle", title_width)
    separator()
    append(single_line(item.message), "NotificationToolsBody")
    if item.details and item.details ~= "" then
      append(" · " .. single_line(item.details), "NotificationToolsMeta")
    end
    if item.source and item.source ~= item.title then
      append(" [" .. single_line(item.source) .. "]", "NotificationToolsSource")
    end
    rows[item] = { text = label, highlights = highlights }
  end
  return rows
end

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
  local rows = columns(items)
  local picker = selection.open({
    prompt = "Notifications",
    kind = "notification-tools-history",
    items = items,
    resume = false, -- Callbacks belong to this notification-tools instance.
    multi = false,
    item_icons = false,
    result_layout = "plain",
    format_item = function(item)
      return rows[item].text
    end,
    highlight_item = function(item)
      return rows[item].highlights
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
