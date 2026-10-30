-- History browsing owns its buffer/navigation; Markdown styles stay shared with popups.
local M = {}
local api = vim.api
local clean = require("notification-tools.layout").clean
local markdown = require("notification-tools.markdown")
local levels = require("notification-tools.config")
local ns
local names = { [0] = "TRACE", "DEBUG", "INFO", "WARN", "ERROR", "OFF" }
local session

function M.options(opts)
  assert(opts == nil or type(opts) == "table", "history options must be a table")
  opts = vim.deepcopy(opts or {})
  if opts.level ~= nil then
    opts.level = levels.level(opts.level)
  end
  for _, key in ipairs({ "source", "title" }) do
    assert(opts[key] == nil or type(opts[key]) == "string", key .. " must be a string")
  end
  return opts
end

function M.filter(items, opts)
  opts = M.options(opts)
  return vim.tbl_filter(function(item)
    return (not opts.level or item.level >= opts.level)
      and (not opts.source or (item.source or item.title) == opts.source)
      and (not opts.title or item.title:lower():find(opts.title:lower(), 1, true) ~= nil)
  end, items)
end

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

function M.highlights()
  local s = session
  if not s or not valid(s) then
    return
  end
  api.nvim_buf_clear_namespace(s.buf, ns, 0, -1)
  for _, mark in ipairs(s.marks) do
    local options = {
      end_col = mark.finish,
      hl_group = "NotificationTools" .. s.styled(mark.hl, mark.style),
      priority = 100,
    }
    if mark.conceal then
      options.conceal, options.priority = "", 200
    end
    api.nvim_buf_set_extmark(s.buf, ns, mark.row, mark.col, options)
  end
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

local function redraw(s, preserve)
  if not valid(s) then
    return
  end
  local cursor = api.nvim_win_get_cursor(s.win)
  local anchor = preserve and selected(s, cursor[1])
  local saved = preserve and api.nvim_win_call(s.win, vim.fn.winsaveview)
  local lines, marks, entries = {}, {}, {}
  local items = M.filter(s.provider(), s.filters)
  -- Providers keep the public oldest-first snapshot; only the UI reverses it.
  for index = #items, 1, -1 do
    local item = items[index]
    local row, header = #lines, ""
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
        marks[#marks + 1] = { row = row, col = col, finish = #header, hl = chunk[2] }
      end
    end
    local first = #lines + 1
    lines[#lines + 1] = header
    local function content(text, group)
      text = clean(text)
      local offset = #lines
      vim.list_extend(lines, vim.split(text, "\n", { plain = true }))
      for _, mark in ipairs(markdown.source(text, group, item.markdown)) do
        mark.row = mark.row + offset
        marks[#marks + 1] = mark
      end
    end
    content(item.message, "Body")
    if item.details and item.details ~= "" then
      content(item.details, "Meta")
    end
    lines[#lines + 1] = ""
    entries[#entries + 1] = { item = item, first = first, last = #lines }
  end
  if #lines == 0 then
    lines = { "No notifications" }
    marks = { { row = 0, col = 0, finish = #lines[1], hl = "Meta" } }
  end
  s.entries, s.marks = entries, marks
  vim.bo[s.buf].modifiable = true
  api.nvim_buf_set_lines(s.buf, 0, -1, false, lines)
  vim.bo[s.buf].modifiable = false
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
  api.nvim_win_set_config(
    s.win,
    geometry(#lines, label .. (s.detail and " " or " · " .. #items .. " "), s.zindex)
  )
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
