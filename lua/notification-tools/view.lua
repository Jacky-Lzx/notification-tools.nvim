local M = {}
local layout = require("notification-tools.layout")
local model = require("notification-tools.state")
local markdown = require("notification-tools.markdown")
local fade_cache = {}
local style_cache = {}
local api = vim.api
local ns = api.nvim_create_namespace("notification-tools")
local windows = {}
local history_win
local history_marks
local refresh_history
local names = { [0] = "TRACE", "DEBUG", "INFO", "WARN", "ERROR", "OFF" }

function M.highlights()
  fade_cache = {}
  style_cache = {}
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
    Done = "DiagnosticOk",
  }) do
    api.nvim_set_hl(0, "NotificationTools" .. name, { default = true, link = link })
  end
  local float = api.nvim_get_hl(0, { name = "NormalFloat", link = false })
  local normal = api.nvim_get_hl(0, { name = "Normal", link = false })
  for _, name in ipairs({ "Body", "TaskTitle" }) do
    api.nvim_set_hl(0, "NotificationTools" .. name, { default = true, fg = float.fg or normal.fg })
  end
  if refresh_history then
    refresh_history()
  end
end

local function styled(key, style)
  if not style then
    return key
  end
  local name = key .. "Markdown" .. style
  local definition = api.nvim_get_hl(0, { name = "NotificationTools" .. key, link = false })
  definition.default = nil
  if style:find("Bold", 1, true) then
    definition.bold = true
  end
  if style:find("Italic", 1, true) then
    definition.italic = true
  end
  if style:find("Strike", 1, true) then
    definition.strikethrough = true
  end
  if not vim.deep_equal(style_cache[name], definition) then
    api.nvim_set_hl(0, "NotificationTools" .. name, definition)
    style_cache[name] = definition
  end
  return name
end

refresh_history = function()
  if not history_win or not api.nvim_win_is_valid(history_win) then
    history_marks = nil
    return
  end
  local buf = api.nvim_win_get_buf(history_win)
  api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, mark in ipairs(history_marks or {}) do
    local options = {
      end_col = mark.finish,
      hl_group = "NotificationTools" .. styled(mark.hl, mark.style),
      priority = 100,
    }
    if mark.conceal then
      options.conceal, options.priority = "", 200
    end
    api.nvim_buf_set_extmark(buf, ns, mark.row, mark.col, options)
  end
end

local clean = layout.clean
M.wrap = layout.wrap

local function close(key)
  local entry = windows[key]
  if entry then
    if api.nvim_win_is_valid(entry.win) then
      api.nvim_win_close(entry.win, true)
    end
    if api.nvim_buf_is_valid(entry.buf) then
      api.nvim_buf_delete(entry.buf, { force = true })
    end
    windows[key] = nil
  end
end

function M.close()
  for key in pairs(windows) do
    close(key)
  end
end

function M.close_history()
  if history_win and api.nvim_win_is_valid(history_win) then
    api.nvim_win_close(history_win, true)
  end
  history_win = nil
  history_marks = nil
end

local function mix(foreground, background, opacity)
  local result = 0
  for _, shift in ipairs({ 16, 8, 0 }) do
    local scale = 2 ^ shift
    local fg, bg = math.floor(foreground / scale) % 256, math.floor(background / scale) % 256
    result = result + math.floor(bg + (fg - bg) * opacity + 0.5) * scale
  end
  return result
end

local function faded(key, opacity, surface)
  local base = "NotificationTools" .. key
  local step = math.floor(opacity * 8 + 0.5)
  if step >= 8 then
    return base
  end
  local definition = api.nvim_get_hl(0, { name = base, link = false })
  local normal = api.nvim_get_hl(0, { name = "NotificationTools" .. surface, link = false })
  local editor = api.nvim_get_hl(0, { name = "Normal", link = false })
  local muted = api.nvim_get_hl(0, { name = "Comment", link = false })
  local foreground = definition.fg or normal.fg or editor.fg
  local background = definition.bg or normal.bg or editor.bg or muted.fg
  if not foreground or not background then
    return base
  end
  definition.default = nil
  definition.fg = mix(foreground, background, step / 8)
  local name = base .. "Fade" .. surface .. step
  if not vim.deep_equal(fade_cache[name], definition) then
    api.nvim_set_hl(0, name, definition)
    fade_cache[name] = definition
  end
  return name
end

local function draw(key, plan, row, config, opacity, fade_out, now)
  local entry = windows[key]
  if entry and (not api.nvim_win_is_valid(entry.win) or not api.nvim_buf_is_valid(entry.buf)) then
    close(key)
    entry = nil
  end
  local options = {
    relative = "editor",
    anchor = "NW",
    row = row,
    col = vim.o.columns - config.right - plan.width - layout.border(config),
    width = plan.width,
    height = #plan.lines,
    style = "minimal",
    border = config.border,
    focusable = false,
    zindex = config.zindex,
    noautocmd = true,
  }
  if not entry then
    local buf = api.nvim_create_buf(false, true)
    vim.bo[buf].bufhidden = "wipe"
    vim.bo[buf].filetype = "notification-tools"
    entry = { buf = buf, win = api.nvim_open_win(buf, false, options) }
    windows[key] = entry
  elseif not vim.deep_equal(entry.options, options) then
    api.nvim_win_set_config(entry.win, options)
  end
  entry.options, entry.width = options, plan.width
  local normal = key == "progress" and "ProgressNormal" or "NotificationNormal"
  vim.wo[entry.win].winhighlight = "Normal:NotificationTools"
    .. normal
    .. ",FloatBorder:NotificationToolsBorder"
  vim.wo[entry.win].winblend =
    math.floor(config.winblend + (100 - config.winblend) * (1 - (opacity or 1)))
  vim.wo[entry.win].wrap = false
  local content_changed = not vim.deep_equal(entry.lines, plan.lines)
  if content_changed then
    vim.bo[entry.buf].modifiable = true
    api.nvim_buf_set_lines(entry.buf, 0, -1, false, plan.lines)
    vim.bo[entry.buf].modifiable = false
    entry.lines = plan.lines
  end
  local marks = {}
  for _, mark in ipairs(plan.marks) do
    marks[#marks + 1] = {
      row = mark.row,
      col = mark.col,
      finish = mark.finish,
      hl = faded(
        styled(mark.hl, mark.style),
        opacity or model.opacity(mark.item, fade_out, now),
        normal
      ),
    }
  end
  if content_changed or not vim.deep_equal(entry.marks, marks) then
    api.nvim_buf_clear_namespace(entry.buf, ns, 0, -1)
    for _, mark in ipairs(marks) do
      api.nvim_buf_set_extmark(
        entry.buf,
        ns,
        mark.row,
        mark.col,
        { end_col = mark.finish, hl_group = mark.hl }
      )
    end
    entry.marks = marks
  end
end

local function notice_key(notice)
  return "notice:" .. type(notice.id) .. ":" .. tostring(notice.id)
end

function M.render(state)
  local config = state.config
  local n, p = config.notification.window, config.progress.window
  local tabline = vim.o.showtabline == 2
    or (vim.o.showtabline == 1 and #api.nvim_list_tabpages() > 1)
  local top = n.top + (tabline and 1 or 0)
  local screen_bottom = vim.o.lines - vim.o.cmdheight - (vim.o.laststatus > 0 and 1 or 0)
  local bottom = screen_bottom - n.bottom
  local notices = model.sorted(state.notices)
  local tasks = model.sorted(state.tasks, true)
  local used, now = {}, model.now()
  if
    config.progress.enabled
    and #tasks > 0
    and not vim.tbl_contains(config.progress.avoid, vim.bo.filetype)
  then
    local progress_top = p.top + (tabline and 1 or 0)
    local available = screen_bottom - p.bottom - progress_top
    local shared = screen_bottom - math.max(n.bottom, p.bottom) - math.max(top, progress_top)
    local budget = #notices > 0 and math.min(available, math.floor(shared / 2)) or available
    local plan = layout.progress(
      tasks,
      config,
      vim.o.columns - p.right - layout.border(p) - 1,
      budget - layout.border(p),
      windows.progress and windows.progress.width,
      now
    )
    if plan then
      local row = screen_bottom - p.bottom - #plan.lines - layout.border(p)
      draw("progress", plan, row, p, nil, config.progress.fade_out, now)
      used.progress = true
      bottom = math.min(bottom, row - math.max(n.gap, p.gap))
    end
  end
  -- Select recent notices first, then display them in creation order. Appending or
  -- updating a notice leaves its neighbours in place while there is room.
  local plans, remaining = {}, bottom - top
  for i = 1, math.min(#notices, config.max_notifications) do
    local notice = notices[i]
    local key = notice_key(notice)
    local plan = layout.notification(
      notice,
      config,
      vim.o.columns - n.right - layout.border(n) - 1,
      remaining - layout.border(n),
      windows[key] and windows[key].width
    )
    if not plan then
      break
    end
    plans[#plans + 1] = { key = key, notice = notice, plan = plan }
    remaining = remaining - #plan.lines - layout.border(n) - n.gap
  end
  local row = top
  for i = #plans, 1, -1 do
    local entry = plans[i]
    draw(
      entry.key,
      entry.plan,
      row,
      n,
      model.opacity(entry.notice, config.notification.fade_out, now),
      nil,
      now
    )
    used[entry.key] = true
    row = row + #entry.plan.lines + layout.border(n) + n.gap
  end
  for key in pairs(windows) do
    if not used[key] then
      close(key)
    end
  end
end

function M.history(items)
  M.close_history()
  local lines, marks = {}, {}
  for _, item in ipairs(items) do
    local row, header = #lines, ""
    for _, chunk in ipairs({
      { os.date("%H:%M:%S", item.time), "Meta" },
      { "  " .. names[item.level] .. "  ", names[item.level] },
      { clean(item.title):gsub("\n", " "), "Title" },
      { (item.count or 1) > 1 and ("  ×" .. item.count) or "", "Meta" },
    }) do
      local col = #header
      header = header .. chunk[1]
      if #header > col then
        marks[#marks + 1] = { row = row, col = col, finish = #header, hl = chunk[2] }
      end
    end
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
  end
  if #lines == 0 then
    lines = { "No notifications" }
    marks = { { row = 0, col = 0, finish = #lines[1], hl = "Meta" } }
  end
  local buf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "notification-tools-history"
  vim.bo[buf].modifiable = false
  local width = math.max(1, math.min(100, vim.o.columns - 4))
  local height = math.max(1, math.min(#lines, vim.o.lines - vim.o.cmdheight - 5))
  history_win = api.nvim_open_win(buf, true, {
    relative = "editor",
    row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1),
    col = math.max(0, math.floor((vim.o.columns - width) / 2) - 1),
    width = width,
    height = height,
    border = "rounded",
    style = "minimal",
    title = " Notifications ",
    title_pos = "center",
  })
  vim.wo[history_win].wrap = true
  vim.wo[history_win].linebreak = true
  vim.wo[history_win].conceallevel = 2
  vim.wo[history_win].concealcursor = "c"
  vim.wo[history_win].winhighlight =
    "Normal:NotificationToolsNormal,FloatBorder:NotificationToolsBorder"
  history_marks = marks
  refresh_history()
  for _, key in ipairs({ "q", "<Esc>" }) do
    vim.keymap.set("n", key, M.close_history, { buffer = buf, silent = true, nowait = true })
  end
end

return M
