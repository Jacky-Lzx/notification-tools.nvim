local M = {}
local api = vim.api
local ns = api.nvim_create_namespace("notification-tools")
local windows = {}
local history_win
local names = { [0] = "TRACE", "DEBUG", "INFO", "WARN", "ERROR", "OFF" }

function M.highlights()
  for name, link in pairs({
    Normal = "NormalFloat",
    Border = "FloatBorder",
    Title = "Title",
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
end

local function clean(text)
  return tostring(text or ""):gsub("\t", "  "):gsub("[%z\1-\8\11-\31\127]", "")
end

-- Split by display cells, preserving multibyte characters and combining marks.
function M.wrap(text, width, limit)
  local lines = {}
  for _, source in ipairs(vim.split(clean(text), "\n", { plain = true })) do
    local line = ""
    for _, char in ipairs(vim.fn.split(source, "\\zs")) do
      if vim.fn.strdisplaywidth(line .. char) > width then
        if line ~= "" then
          lines[#lines + 1] = line
          if limit and #lines >= limit then
            return lines
          end
        end
        line = vim.fn.strdisplaywidth(char) <= width and char or "?"
      else
        line = line .. char
      end
    end
    lines[#lines + 1] = line
    if limit and #lines >= limit then
      return lines
    end
  end
  return lines
end

local function clip(text, width)
  local lines = M.wrap(text, width)
  if #lines > 1 and width > 1 then
    return M.wrap(lines[1], width - 1)[1] .. "…"
  end
  return lines[1]
end

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
end

local function draw(key, lines, row, col, width, config, marks)
  local entry = windows[key]
  if entry and (not api.nvim_win_is_valid(entry.win) or not api.nvim_buf_is_valid(entry.buf)) then
    close(key)
    entry = nil
  end
  local options = {
    relative = "editor",
    anchor = "NW",
    row = row,
    col = col,
    width = width,
    height = #lines,
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
  else
    api.nvim_win_set_config(entry.win, options)
  end
  vim.wo[entry.win].winblend = config.winblend
  vim.wo[entry.win].winhighlight =
    "Normal:NotificationToolsNormal,FloatBorder:NotificationToolsBorder"
  vim.wo[entry.win].wrap = false
  if not vim.deep_equal(entry.lines, lines) then
    vim.bo[entry.buf].modifiable = true
    api.nvim_buf_set_lines(entry.buf, 0, -1, false, lines)
    vim.bo[entry.buf].modifiable = false
    entry.lines = lines
  end
  api.nvim_buf_clear_namespace(entry.buf, ns, 0, -1)
  for _, mark in ipairs(marks) do
    api.nvim_buf_set_extmark(entry.buf, ns, mark[1], 0, {
      end_col = #lines[mark[1] + 1],
      hl_group = "NotificationTools" .. mark[2],
    })
  end
end

function M.render(state)
  local config = state.config
  local c = config.window
  local tabline = vim.o.showtabline == 2
    or (vim.o.showtabline == 1 and #api.nvim_list_tabpages() > 1)
  local top = c.top + (tabline and 1 or 0)
  local bottom = vim.o.lines - vim.o.cmdheight - (vim.o.laststatus > 0 and 1 or 0) - c.bottom
  local border = c.border ~= "none" and c.border ~= "" and 2 or 0
  local width = math.min(c.max_width, vim.o.columns - c.right - border - 1)
  local available = bottom - top
  if width < 4 or available < 3 + border then
    M.close()
    return
  end
  local notices = require("notification-tools.state").sorted(state.notices)
  local tasks = require("notification-tools.state").sorted(state.tasks)
  local avoid = vim.tbl_contains(config.progress.avoid, vim.bo.filetype)
  local used = {}
  local progress_height = 0
  if config.progress.enabled and #tasks > 0 and not avoid then
    local budget = #notices > 0 and math.floor(available / 2) or available
    local height = math.min(#tasks, config.progress.max_items, budget - border)
    if height >= 1 then
      local lines, marks = {}, {}
      local frames = config.progress.spinner
      local frame = frames[math.floor(
        require("notification-tools.state").now() / config.progress.interval
      ) % #frames + 1]
      for i = 1, height do
        local task = tasks[i]
        local icon = task.done
            and (task.status == "error" and "✖" or task.status == "cancelled" and "−" or "✔")
          or frame
        local percent = task.percentage and (" %d%%"):format(task.percentage) or ""
        local text = icon .. " " .. task.title .. percent
        if task.source ~= "" then
          text = text .. " [" .. task.source .. "]"
        end
        if task.message ~= "" then
          text = text .. " · " .. task.message
        end
        if i == height and #tasks > height and height > 1 then
          text = "+" .. (#tasks - height + 1) .. " more tasks"
        end
        lines[i] = clip(text, width)
        marks[i] =
          { i - 1, task.done and (task.status == "error" and "ERROR" or "Done") or "Progress" }
      end
      progress_height = height + border + 1
      draw(
        "progress",
        lines,
        bottom - height - border,
        vim.o.columns - c.right - width - border,
        width,
        c,
        marks
      )
      used.progress = true
    end
  end
  local row = top
  for index, notice in ipairs(notices) do
    if index > config.max_notifications then
      break
    end
    local budget = bottom - progress_height - row - border
    if budget < 2 then
      break
    end
    local level = names[notice.level]
    local header = (notice.icon or config.icons[level] or "●") .. " " .. notice.title
    local natural = math.max(c.min_width, vim.fn.strdisplaywidth(clean(header)))
    for _, line in ipairs(vim.split(clean(notice.message), "\n", { plain = true })) do
      natural = math.max(natural, vim.fn.strdisplaywidth(line))
    end
    local w = math.min(width, natural)
    local body = M.wrap(notice.message, w, c.max_height + 1)
    local lines = { clip(header, w) }
    local count = math.min(#body, c.max_height, budget - 1)
    for i = 1, count do
      lines[#lines + 1] = body[i]
    end
    if count < #body then
      lines[#lines] = clip(lines[#lines] .. " …", w)
    end
    local key = "notice:" .. type(notice.id) .. ":" .. tostring(notice.id)
    draw(key, lines, row, vim.o.columns - c.right - w - border, w, c, { { 0, level } })
    used[key] = true
    row = row + #lines + border + 1
  end
  for key in pairs(windows) do
    if not used[key] then
      close(key)
    end
  end
end

function M.history(items)
  M.close_history()
  local lines = {}
  for _, item in ipairs(items) do
    lines[#lines + 1] = os.date("%H:%M:%S", item.time)
      .. "  "
      .. names[item.level]
      .. "  "
      .. clean(item.title):gsub("\n", " ")
    vim.list_extend(lines, vim.split(clean(item.message), "\n", { plain = true }))
    lines[#lines + 1] = ""
  end
  if #lines == 0 then
    lines = { "No notifications" }
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
  for _, key in ipairs({ "q", "<Esc>" }) do
    vim.keymap.set("n", key, M.close_history, { buffer = buf, silent = true, nowait = true })
  end
end

return M
