local M = {}
local layout = require("notification-tools.layout")
local model = require("notification-tools.state")
local fade_cache = {}
local style_cache = {}
local api = vim.api
local ns = api.nvim_create_namespace("notification-tools")
local windows = {}
local frame_highlights
local function highlight(name)
  if not frame_highlights then
    return api.nvim_get_hl(0, { name = name, link = false })
  end
  if not frame_highlights[name] then
    frame_highlights[name] = api.nvim_get_hl(0, { name = name, link = false })
  end
  return vim.deepcopy(frame_highlights[name])
end

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
  local normal = highlight("Normal")
  for _, name in ipairs({ "Body", "TaskTitle" }) do
    api.nvim_set_hl(0, "NotificationTools" .. name, { default = true, fg = float.fg or normal.fg })
  end
  if package.loaded["notification-tools.history"] then
    require("notification-tools.history").highlights()
  end
end

local function styled(key, style)
  if not style then
    return key
  end
  local name = key .. "Markdown" .. style
  local definition = highlight("NotificationTools" .. key)
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
  if package.loaded["notification-tools.history"] then
    require("notification-tools.history").close()
  end
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
  local definition = highlight(base)
  local normal = highlight("NotificationTools" .. surface)
  local editor = highlight("Normal")
  local muted = highlight("Comment")
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
  if
    entry
    and (
      not api.nvim_win_is_valid(entry.win)
      or not api.nvim_buf_is_valid(entry.buf)
      or api.nvim_win_get_tabpage(entry.win) ~= api.nvim_get_current_tabpage()
    )
  then
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
  local winhighlight = "Normal:NotificationTools"
    .. normal
    .. ",FloatBorder:NotificationToolsBorder"
  if entry.winhighlight ~= winhighlight then
    vim.wo[entry.win].winhighlight = winhighlight
    vim.wo[entry.win].wrap = false
    entry.winhighlight = winhighlight
  end
  local blend = math.floor(config.winblend + (100 - config.winblend) * (1 - (opacity or 1)))
  if entry.blend ~= blend then
    vim.wo[entry.win].winblend = blend
    entry.blend = blend
  end
  local rows = {}
  for _, mark in ipairs(plan.marks) do
    local row = mark.row + 1
    rows[row] = rows[row] or {}
    rows[row][#rows[row] + 1] = {
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
  local structural = not entry.lines or #entry.lines ~= #plan.lines
  local content_changed = not vim.deep_equal(entry.lines, plan.lines)
  if content_changed then
    vim.bo[entry.buf].modifiable = true
  end
  if structural then
    api.nvim_buf_clear_namespace(entry.buf, ns, 0, -1)
    api.nvim_buf_set_lines(entry.buf, 0, -1, false, plan.lines)
  end
  for row, line in ipairs(plan.lines) do
    local changed_text = not structural and entry.lines[row] ~= line
    local changed_marks = structural
      or changed_text
      or not vim.deep_equal((entry.row_marks or {})[row], rows[row])
    if changed_marks then
      if not structural then
        api.nvim_buf_clear_namespace(entry.buf, ns, row - 1, row)
      end
      if changed_text then
        api.nvim_buf_set_lines(entry.buf, row - 1, row, false, { line })
      end
      for _, mark in ipairs(rows[row] or {}) do
        api.nvim_buf_set_extmark(
          entry.buf,
          ns,
          mark.row,
          mark.col,
          { end_col = mark.finish, hl_group = mark.hl }
        )
      end
    end
  end
  if content_changed then
    vim.bo[entry.buf].modifiable = false
  end
  entry.lines, entry.row_marks = plan.lines, rows
end

local function notice_key(notice)
  return "notice:" .. type(notice.id) .. ":" .. tostring(notice.id)
end

function M.render(state)
  frame_highlights = {}
  local config = state.config
  local n, p = config.notification.window, config.progress.window
  local tabline = vim.o.showtabline == 2
    or (vim.o.showtabline == 1 and #api.nvim_list_tabpages() > 1)
  local top = n.top + (tabline and 1 or 0)
  local screen_bottom = vim.o.lines - vim.o.cmdheight - (vim.o.laststatus > 0 and 1 or 0)
  local bottom = screen_bottom - n.bottom
  local notices = vim.tbl_filter(function(notice)
    return notice.display ~= false
  end, model.sorted(state.notices))
  local tasks = model.sorted(state.tasks, true)
  local used, now = {}, model.now()
  local visible = { notices = {}, tasks = {} }
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
      for i = 1, plan.displayed do
        visible.tasks[tasks[i].id] = true
      end
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
    visible.notices[entry.notice.id] = true
    row = row + #entry.plan.lines + layout.border(n) + n.gap
  end
  for key in pairs(windows) do
    if not used[key] then
      close(key)
    end
  end
  frame_highlights = nil
  return visible
end

function M.history(provider, opts, on_select, zindex)
  require("notification-tools.history").open(
    provider,
    opts,
    styled,
    { select = on_select, zindex = zindex }
  )
end

function M.notification(provider, on_close, zindex)
  require("notification-tools.history").open(
    provider,
    {},
    styled,
    { detail = true, close = on_close, zindex = zindex }
  )
end

return M
