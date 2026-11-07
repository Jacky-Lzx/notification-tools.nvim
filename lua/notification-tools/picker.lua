-- Optional selection-tools consumer; notification capture never loads this module.
local M = {}
local active
local api = vim.api
local preview_ns = api.nvim_create_namespace("notification-tools-preview")
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
    local body_start, body_mark = #label, #highlights
    append(single_line(item.message), "NotificationToolsBody")
    if item.details and item.details ~= "" then
      append(" · " .. single_line(item.details), "NotificationToolsMeta")
    end
    if item.source and item.source ~= item.title then
      append(" [" .. single_line(item.source) .. "]", "NotificationToolsSource")
    end
    local body_highlights = {}
    for i = body_mark + 1, #highlights do
      local mark = highlights[i]
      body_highlights[#body_highlights + 1] =
        { mark[1] - body_start, mark[2] - body_start, hl = mark.hl }
    end
    rows[item] = {
      text = label,
      highlights = highlights,
      title = titles[item],
      body = label:sub(body_start + 1),
      body_highlights = body_highlights,
    }
  end
  return rows
end

local function heading(item)
  local line, marks = "", {}
  local level = names[item.level]
  for _, chunk in ipairs({
    { os.date("%H:%M:%S", item.time), "Meta" },
    { "  " .. level .. "  ", level == "OFF" and "Meta" or level },
    { single_line(item.title), "Title" },
    {
      item.source and item.source ~= item.title and (" [" .. single_line(item.source) .. "]") or "",
      "Source",
    },
    { (item.count or 1) > 1 and (" ×" .. item.count) or "", "Meta" },
  }) do
    local col = #line
    line = line .. chunk[1]
    if #line > col then
      marks[#marks + 1] = { row = 0, col = col, finish = #line, hl = chunk[2] }
    end
  end
  return line, marks
end

local function preview(ctx)
  local item = ctx.item
  local header, marks = heading(item)
  local lines = { header, "" }
  local function content(value, group, filetype, spans)
    local offset = #lines
    vim.list_extend(
      lines,
      vim.split(require("notification-tools.text").clean(value), "\n", { plain = true })
    )
    for _, mark in
      ipairs(
        require("notification-tools.content").source(value, group, item.markdown, filetype, spans)
      )
    do
      mark.row = mark.row + offset
      marks[#marks + 1] = mark
    end
  end
  content(item.message, "Body", item.filetype, item.spans)
  if item.details and item.details ~= "" then
    lines[#lines + 1] = ""
    content(item.details, "Meta")
  end
  -- Publish text and marks together, guarded by selection-tools against stale
  -- previews. Each entry replaces the previous entry's marks in our namespace.
  local painted
  ctx.paint(function(buf, win)
    painted = buf
    api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].filetype = item.filetype or (item.markdown and "markdown" or "text")
    vim.bo[buf].syntax = ""
    pcall(vim.treesitter.stop, buf)
    api.nvim_buf_clear_namespace(buf, preview_ns, 0, -1)
    for _, mark in ipairs(marks) do
      local options =
        { end_col = mark.finish, hl_group = "NotificationTools" .. mark.hl, priority = 100 }
      if mark.conceal then
        options.conceal, options.priority = "", 200
      end
      api.nvim_buf_set_extmark(buf, preview_ns, mark.row, mark.col, options)
      if mark.style then
        api.nvim_buf_set_extmark(buf, preview_ns, mark.row, mark.col, {
          end_col = mark.finish,
          hl_group = "NotificationToolsPreview" .. mark.style,
          hl_mode = "combine",
          priority = 101,
        })
      end
    end
    vim.wo[win].conceallevel, vim.wo[win].concealcursor = 2, "nvic"
  end, { title = item.title })
  return function()
    if painted and api.nvim_buf_is_valid(painted) then
      api.nvim_buf_clear_namespace(painted, preview_ns, 0, -1)
    end
  end
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
    components = {
      { kind = "time", field = "time", format = "%H:%M:%S", searchable = true },
      {
        kind = "text",
        get = function()
          return "│"
        end,
        searchable = false,
        hl = "NotificationToolsMeta",
      },
      {
        kind = "text",
        width = 5,
        hl = false,
        get = function(item)
          return names[item.level]
        end,
        highlights = function(item)
          local level = names[item.level]
          return {
            {
              0,
              #level,
              hl = level == "OFF" and "NotificationToolsMeta" or ("NotificationTools" .. level),
            },
          }
        end,
      },
      {
        kind = "text",
        get = function()
          return "│"
        end,
        searchable = false,
        hl = "NotificationToolsMeta",
      },
      {
        kind = "text",
        get = function(item)
          return rows[item].title
        end,
        hl = "NotificationToolsTitle",
        max_width = 30,
        priority = 80,
      },
      {
        kind = "text",
        get = function()
          return "│"
        end,
        searchable = false,
        hl = "NotificationToolsMeta",
      },
      {
        kind = "text",
        grow = 1,
        min_width = 12,
        truncate = "match",
        hl = false,
        get = function(item)
          return rows[item].body
        end,
        highlights = function(item)
          return rows[item].body_highlights
        end,
      },
    },
    preview = { enabled = true, highlight_line = false, highlight_matches = false },
    previewer = preview,
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
