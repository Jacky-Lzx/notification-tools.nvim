-- History browsing owns its buffer/navigation; Markdown styles stay shared with popups.
local M = {}
local api = vim.api
local clean = require("notification-tools.layout").clean
local markdown = require("notification-tools.markdown")
local levels = require("notification-tools.config")
local ns
local names = { [0] = "TRACE", "DEBUG", "INFO", "WARN", "ERROR", "OFF" }
local session

M.options = require("notification-tools.records").options
M.filter = require("notification-tools.records").filter

local function valid(s)
  return session == s and api.nvim_win_is_valid(s.win) and api.nvim_buf_is_valid(s.buf)
end

local function finish(s)
  if s.closed then
    return
  end
  s.closed = true
  if session == s then
    session = nil
  end
  if s.on_close then
    s.on_close()
  end
end

function M.close()
  local s = session
  if not s then
    return
  end
  session = nil
  if api.nvim_win_is_valid(s.win) then
    api.nvim_win_close(s.win, true)
  end
  finish(s)
end

function M.close_hidden()
  if
    session
    and api.nvim_win_is_valid(session.win)
    and api.nvim_win_get_tabpage(session.win) ~= api.nvim_get_current_tabpage()
  then
    M.close()
  end
end

function M.highlights()
  local s = session
  if not s or not valid(s) then
    return
  end
  local changed = not vim.deep_equal(s.applied_marks, s.marks)
  if changed then
    api.nvim_buf_clear_namespace(s.buf, ns, 0, -1)
  end
  local groups = {}
  for _, mark in ipairs(s.marks) do
    local key = mark.hl .. ":" .. (mark.style or "")
    if not groups[key] then
      groups[key] = "NotificationTools" .. s.styled(mark.hl, mark.style)
    end
    if changed then
      local options = { end_col = mark.finish, hl_group = groups[key], priority = 100 }
      if mark.conceal then
        options.conceal, options.priority = "", 200
      end
      api.nvim_buf_set_extmark(s.buf, ns, mark.row, mark.col, options)
    end
  end
  s.applied_marks = s.marks
end

local function selected(s, row)
  for _, entry in ipairs(s.entries) do
    if row >= entry.first and row <= entry.last then
      return entry
    end
  end
end

local function geometry(count, title, zindex)
  local width = math.max(1, math.min(100, vim.o.columns - 4))
  local height = math.max(1, math.min(count, vim.o.lines - vim.o.cmdheight - 5))
  return {
    relative = "editor",
    row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1),
    col = math.max(0, math.floor((vim.o.columns - width) / 2) - 1),
    width = width,
    height = height,
    border = "rounded",
    style = "minimal",
    title = title,
    title_pos = "center",
    zindex = zindex or 151,
  }
end

-- Cache per-record layout and body spans separately so repeat-count/header
-- updates do not reparse unchanged Markdown. All cached rows stay relative.
local function formatted(item, cached)
  if cached and cached.item == item then
    return cached
  end
  local body = cached and cached.body
  if
    not body
    or body.message ~= item.message
    or body.details ~= item.details
    or body.markdown ~= item.markdown
  then
    body = {
      lines = {},
      marks = {},
      message = item.message,
      details = item.details,
      markdown = item.markdown,
    }
    local function content(value, group)
      value = clean(value)
      local offset = #body.lines
      vim.list_extend(body.lines, vim.split(value, "\n", { plain = true }))
      for _, mark in ipairs(markdown.source(value, group, item.markdown)) do
        mark.row = mark.row + offset
        body.marks[#body.marks + 1] = mark
      end
    end
    content(item.message, "Body")
    if item.details and item.details ~= "" then
      content(item.details, "Meta")
    end
  end
  local header, marks = "", {}
  for _, chunk in ipairs({
    { os.date("%H:%M:%S", item.time), "Meta" },
    { "  " .. names[item.level] .. "  ", names[item.level] },
    { clean(item.title):gsub("\n", " "), "Title" },
    {
      item.source and item.source ~= "" and item.source ~= item.title and ("  [" .. clean(
        item.source
      ):gsub("\n", " ") .. "]") or "",
      "Source",
    },
    { (item.count or 1) > 1 and ("  ×" .. item.count) or "", "Meta" },
  }) do
    local col = #header
    header = header .. chunk[1]
    if #header > col then
      marks[#marks + 1] = { row = 0, col = col, finish = #header, hl = chunk[2] }
    end
  end
  local lines = { header }
  vim.list_extend(lines, body.lines)
  lines[#lines + 1] = ""
  for _, mark in ipairs(body.marks) do
    local copy = vim.tbl_extend("force", {}, mark)
    copy.row = copy.row + 1
    marks[#marks + 1] = copy
  end
  return { item = item, body = body, lines = lines, marks = marks }
end

local function redraw(s, preserve)
  if not valid(s) then
    return
  end
  local cursor = api.nvim_win_get_cursor(s.win)
  local anchor = preserve and selected(s, cursor[1])
  local saved = preserve and api.nvim_win_call(s.win, vim.fn.winsaveview)
  local lines, marks, entries = {}, {}, {}
  local records = s.provider()
  local alive = {}
  for _, item in ipairs(records) do
    alive[item.id] = true
  end
  for id in pairs(s.cache) do
    if not alive[id] then
      s.cache[id] = nil
    end
  end
  local items = M.filter(records, s.filters)
  -- Providers keep the public oldest-first snapshot; only the UI reverses it.
  for index = #items, 1, -1 do
    local item = items[index]
    local cached = formatted(item, s.cache[item.id])
    s.cache[item.id] = cached
    local offset = #lines
    vim.list_extend(lines, cached.lines)
    for _, mark in ipairs(cached.marks) do
      local copy = vim.tbl_extend("force", {}, mark)
      copy.row = copy.row + offset
      marks[#marks + 1] = copy
    end
    entries[#entries + 1] = { item = item, first = offset + 1, last = #lines }
  end
  if #lines == 0 then
    lines = { "No notifications" }
    marks = { { row = 0, col = 0, finish = #lines[1], hl = "Meta" } }
  end
  s.entries, s.marks = entries, marks
  if not vim.deep_equal(s.lines, lines) then
    vim.bo[s.buf].modifiable = true
    api.nvim_buf_set_lines(s.buf, 0, -1, false, lines)
    vim.bo[s.buf].modifiable = false
    -- Rewriting the buffer can relocate marks even if the next ranges match.
    s.applied_marks = nil
  end
  s.lines = lines
  local label = s.detail and " Notification" or " Notifications"
  if s.filters.level then
    label = label .. " · " .. names[s.filters.level] .. "+"
  end
  if s.filters.source then
    label = label .. " · " .. clean(s.filters.source):gsub("\n", " ")
  end
  if s.filters.title then
    label = label .. " · " .. clean(s.filters.title):gsub("\n", " ")
  end
  local window = geometry(#lines, label .. (s.detail and " " or " · " .. #items .. " "), s.zindex)
  if not vim.deep_equal(s.geometry, window) then
    api.nvim_win_set_config(s.win, window)
    s.geometry = window
  end
  M.highlights()
  if preserve then
    local row = math.min(cursor[1], #lines)
    if anchor then
      for _, entry in ipairs(entries) do
        if entry.item.id == anchor.item.id then
          row = math.min(entry.last, entry.first + cursor[1] - anchor.first)
          break
        end
      end
    end
    saved.topline = math.max(1, saved.topline + row - cursor[1])
    saved.lnum, saved.col = row, math.min(cursor[2], #lines[row])
    api.nvim_win_call(s.win, function()
      vim.fn.winrestview(saved)
    end)
  else
    api.nvim_win_set_cursor(s.win, { 1, 0 })
  end
end

function M.refresh()
  if session then
    redraw(session, true)
  end
end

function M.jump(direction)
  local s = session
  if not s or not valid(s) then
    return
  end
  local row = api.nvim_win_get_cursor(s.win)[1]
  local target
  if direction > 0 then
    for _, entry in ipairs(s.entries) do
      if entry.first > row then
        target = entry.first
        break
      end
    end
  else
    for i = #s.entries, 1, -1 do
      if s.entries[i].first < row then
        target = s.entries[i].first
        break
      end
    end
  end
  if target then
    api.nvim_win_set_cursor(s.win, { target, 0 })
  end
end

function M.open(provider, opts, styled, handlers)
  handlers = handlers or {}
  ns = ns or api.nvim_create_namespace("notification-tools")
  M.close()
  local buf = api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "notification-tools-history"
  local win = api.nvim_open_win(buf, true, geometry(1, " Notifications ", handlers.zindex))
  session = {
    win = win,
    buf = buf,
    provider = provider,
    filters = M.options(opts),
    styled = styled,
    entries = {},
    marks = {},
    cache = {},
    detail = handlers.detail,
    zindex = handlers.zindex,
    on_close = handlers.close,
  }
  local s = session
  vim.b[buf].notification_tools_detail = s.detail == true
  api.nvim_create_autocmd({ "BufWipeout", "BufWinLeave" }, {
    buffer = buf,
    once = true,
    callback = function()
      finish(s)
    end,
  })
  vim.wo[win].wrap, vim.wo[win].linebreak = true, true
  vim.wo[win].conceallevel, vim.wo[win].concealcursor = 2, "c"
  vim.wo[win].winhighlight = "Normal:NotificationToolsNormal,FloatBorder:NotificationToolsBorder"
  redraw(s, false)
  local function map(key, callback, desc)
    vim.keymap.set("n", key, callback, { buffer = buf, silent = true, nowait = true, desc = desc })
  end
  for _, key in ipairs({ "q", "<Esc>" }) do
    map(key, M.close, "Close history")
  end
  map("r", M.refresh, "Refresh notification contents")
  if s.detail then
    return
  end
  if handlers.select then
    map("<CR>", function()
      local entry = selected(s, api.nvim_win_get_cursor(s.win)[1])
      if entry then
        handlers.select(entry.item.id)
      end
    end, "Read selected notification")
  end
  map("R", function()
    s.filters = {}
    redraw(s, true)
  end, "Reset history filters")
  map("]n", function()
    M.jump(1)
  end, "Next notification")
  map("[n", function()
    M.jump(-1)
  end, "Previous notification")
  map("gl", function()
    vim.ui.select(
      { "ALL", "TRACE", "DEBUG", "INFO", "WARN", "ERROR" },
      { prompt = "Minimum notification level:" },
      function(value)
        if not value or not valid(s) then
          return
        end
        s.filters.level = value ~= "ALL" and levels.level(value) or nil
        redraw(s, true)
      end
    )
  end, "Filter by level")
  map("gs", function()
    local sources = {}
    for _, item in ipairs(s.provider()) do
      sources[item.source or item.title] = true
    end
    local choices = vim.tbl_keys(sources)
    table.sort(choices)
    table.insert(choices, 1, false)
    vim.ui.select(choices, {
      prompt = "Notification source:",
      format_item = function(value)
        return value == false and "All sources" or value
      end,
    }, function(value)
      if value == nil or not valid(s) then
        return
      end
      s.filters.source = value or nil
      redraw(s, true)
    end)
  end, "Filter by source")
  map("gt", function()
    vim.ui.input({ prompt = "Title contains: ", default = s.filters.title or "" }, function(value)
      if value == nil or not valid(s) then
        return
      end
      s.filters.title = value ~= "" and value or nil
      redraw(s, true)
    end)
  end, "Filter by title")
end

return M
