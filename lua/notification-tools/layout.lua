local M = {}
local model = require("notification-tools.state")
local markdown
local content
local text = require("notification-tools.text")
local text_cache = setmetatable({}, { __mode = "k" })
local shared_cache = setmetatable({}, { __mode = "k" })
local plans = setmetatable({}, { __mode = "k" })
local progress_plans = setmetatable({}, { __mode = "k" })

M.clean = text.clean

local function inline(text)
  return M.clean(text):gsub("\n", " ")
end

function M.wrap(value, width, limit)
  local lines, line = {}, ""
  for char in text.chars(M.clean(value)) do
    if char == "\n" then
      lines[#lines + 1], line = line, ""
      if limit and #lines >= limit then
        return lines
      end
    else
      if vim.fn.strdisplaywidth(line .. char) > width then
        if line ~= "" then
          lines[#lines + 1], line = line, ""
          if limit and #lines >= limit then
            return lines
          end
        end
        if vim.fn.strdisplaywidth(char) > width then
          char = "?"
        end
      end
      line = line .. char
    end
  end
  lines[#lines + 1] = line
  return lines
end

function M.clip(text, width)
  if width <= 0 then
    return ""
  end
  local lines = M.wrap(text, width, 2)
  if #lines > 1 then
    local ellipsis = vim.fn.strdisplaywidth("…") <= width and "…" or "."
    local remaining = width - vim.fn.strdisplaywidth(ellipsis)
    return (remaining > 0 and M.wrap(lines[1], remaining, 1)[1] or "") .. ellipsis
  end
  return lines[1]
end

function M.border(config)
  return (config.border == "none" or config.border == "") and 0 or 2
end

local function cells(text)
  return vim.fn.strdisplaywidth(text)
end

local function append(panel, chunks, item)
  local row = #panel.lines
  local line = string.rep(" ", panel.padding)
  for _, chunk in ipairs(chunks) do
    if #chunk[1] > 0 then
      local col = #line
      line = line .. chunk[1]
      panel.marks[#panel.marks + 1] = {
        row = row,
        col = col,
        finish = #line,
        hl = chunk[2] or "Body",
        style = chunk[3],
        item = item,
      }
    end
  end
  panel.lines[#panel.lines + 1] = line .. string.rep(" ", math.max(0, panel.width - cells(line)))
end

local function panel(width, padding)
  return { width = width, padding = padding, lines = {}, marks = {} }
end

local function blank(result)
  append(result, {})
end

local function width_for(config, maximum, minimum, natural)
  return math.min(maximum, config.max_width, math.max(config.min_width, minimum or 0, natural))
end

local function padding(config, width, height, core_height)
  return math.min(config.padding.horizontal, math.max(0, math.floor((width - 6) / 2))),
    math.min(config.padding.vertical, math.max(0, math.floor((height - core_height) / 2)))
end

local function header(left, left_group, right, width)
  right = cells(right) + 4 <= width and right or ""
  left = M.clip(left, width - (right ~= "" and cells(right) + 2 or 0))
  return {
    { left, left_group },
    { string.rep(" ", width - cells(left) - cells(right)) },
    { right, "Meta" },
  }
end

local function formatted(notice, config)
  markdown = markdown or require("notification-tools.markdown")
  content = content or require("notification-tools.content")
  local enabled = notice.markdown
  if enabled == nil then
    enabled = config.notification.markdown
  end
  local shared = shared_cache[config]
  if not shared then
    shared = { entries = {}, order = {} }
    shared_cache[config] = shared
  end
  local cached = text_cache[notice] or shared.entries[notice.content_revision]
  if
    not cached
    or cached.message ~= notice.message
    or cached.details ~= notice.details
    or cached.enabled ~= enabled
    or cached.filetype ~= notice.filetype
    or not vim.deep_equal(cached.spans, notice.spans)
  then
    cached = {
      enabled = enabled,
      filetype = notice.filetype,
      spans = notice.spans,
      message = notice.message,
      details = notice.details,
      body = content.parse(notice.message, "Body", enabled, notice.filetype, nil, notice.spans),
      extra = markdown.parse(M.clean(notice.details), "Meta", enabled),
      widths = {},
    }
    if notice.content_revision then
      shared.entries[notice.content_revision] = cached
      shared.order[#shared.order + 1] = notice.content_revision
      while #shared.order > config.max_pending do
        shared.entries[table.remove(shared.order, 1)] = nil
      end
    end
  end
  text_cache[notice] = cached
  return cached
end

local function notification(notice, config, maximum, height, minimum)
  if maximum < 4 or height < 2 then
    return nil
  end
  local level = ({ [0] = "TRACE", "DEBUG", "INFO", "WARN", "ERROR" })[notice.level]
  local c = config.notification.window
  local content = formatted(notice, config)
  local icon = inline(
    require("notification-tools.icons").get(
      "diagnostic",
      level:lower(),
      notice.icon or config.icons[level] or "●"
    )
  )
  local title = inline(notice.title)
  local indent_width = icon ~= "" and (cells(icon) + 1) or 0
  local meta = (notice.count or 1) > 1 and ("×" .. notice.count)
    or (config.notification.timestamp and os.date("%H:%M", notice.time) or "")
  local heading = (icon ~= "" and (icon .. " ") or "") .. title
  local natural = cells(heading) + (meta ~= "" and cells(meta) + 2 or 0)
  local cap = math.max(0, math.min(maximum, c.max_width) - c.padding.horizontal * 2 - indent_width)
  local metric = text.metrics()
  local key = metric .. ":" .. cap
  if not content.widths[key] then
    content.widths[key] = math.max(text.width(content.body, cap), text.width(content.extra, cap))
  end
  natural = math.max(natural, content.widths[key] + indent_width)
  local width = width_for(c, maximum, minimum, natural + c.padding.horizontal * 2)
  local px, py = padding(c, width, height, 2)
  local inner = width - px * 2
  local result = panel(width, px)
  for _ = 1, py do
    blank(result)
  end
  local chunks = header(heading, "Title", meta, inner)
  -- Separate the icon's severity from the title's normal emphasis, in byte columns.
  local left = chunks[1][1]
  local visible_icon = M.clip(icon, math.max(1, inner - 1))
  if visible_icon ~= "" and left:sub(1, #visible_icon) == visible_icon then
    chunks[1] = { visible_icon, level }
    table.insert(chunks, 2, { left:sub(#visible_icon + 1), "Title" })
  end
  append(result, chunks)
  local indent = math.min(indent_width, math.max(0, inner - 2))
  local body_width = inner - indent
  local body_budget = math.min(c.max_height, height - py * 2 - 1)
  local details = notice.details or ""
  local detail_budget = details ~= "" and body_budget >= 2 and 1 or 0
  local body = markdown.wrap(content.body, body_width, body_budget + 1)
  local count = math.min(#body, body_budget - detail_budget)
  for i = 1, count do
    local line = body[i]
    if i == count and #body > count then
      line = markdown.clip(vim.list_extend(vim.deepcopy(line), { { " …", "Body" } }), body_width)
    end
    append(result, vim.list_extend({ { string.rep(" ", indent) } }, line))
  end
  if detail_budget > 0 then
    append(
      result,
      vim.list_extend(
        { { string.rep(" ", indent) } },
        markdown.clip(content.extra, body_width, "Meta")
      )
    )
  end
  for _ = 1, py do
    blank(result)
  end
  -- A one-cell accent stays inside the horizontal padding, without coloring the body.
  local accent = "▎"
  local accent_width = cells(accent)
  if px >= accent_width then
    for row = py + 1, #result.lines - py do
      local line = result.lines[row]
      result.lines[row] = accent .. line:sub(accent_width + 1)
      for _, mark in ipairs(result.marks) do
        if mark.row == row - 1 then
          mark.col, mark.finish =
            mark.col + #accent - accent_width, mark.finish + #accent - accent_width
        end
      end
      result.marks[#result.marks + 1] = { row = row - 1, col = 0, finish = #accent, hl = level }
    end
  end
  return result
end

function M.notification(notice, config, maximum, height, minimum)
  local key = {
    config,
    maximum,
    height,
    minimum or 0,
    text.metrics(),
    notice.message,
    notice.details,
    notice.title,
    notice.level,
    require("notification-tools.icons").get(
      "diagnostic",
      ({ [0] = "trace", "debug", "info", "warn", "error" })[notice.level],
      notice.icon
        or config.icons[({ [0] = "TRACE", "DEBUG", "INFO", "WARN", "ERROR" })[notice.level]]
        or "●"
    ),
    notice.markdown,
    notice.filetype or "",
    notice.spans or false,
    notice.count or 1,
    notice.time,
  }
  local cached = plans[notice]
  if cached and vim.deep_equal(cached.key, key) then
    return cached.plan
  end
  local plan = notification(notice, config, maximum, height, minimum)
  plans[notice] = { key = key, plan = plan }
  return plan
end

local function status(task)
  if not task.done then
    return "Progress"
  end
  return task.status == "error" and "ERROR" or task.status == "cancelled" and "Cancelled" or "Done"
end

local function elapsed(task, now)
  local seconds = math.max(0, ((task.finished or now) - (task.started or now)) / 1000)
  if seconds >= 3600 then
    return ("%dh%02dm"):format(math.floor(seconds / 3600), math.floor(seconds / 60) % 60)
  end
  if seconds >= 60 then
    return ("%dm%02ds"):format(math.floor(seconds / 60), math.floor(seconds) % 60)
  end
  return ("%.1fs"):format(seconds)
end

-- Completed tasks and unknown totals use a status row, without a decorative bar.
local function bar(task, width)
  local filled, empty = "━", "─"
  local unit = math.max(cells(filled), cells(empty))
  local slots = math.floor(width / unit)
  if slots < 2 then
    return nil
  end
  filled = filled .. string.rep(" ", unit - cells(filled))
  empty = empty .. string.rep(" ", unit - cells(empty))
  local count = math.floor(slots * task.percentage / 100)
  return {
    { string.rep(filled, count), status(task) },
    { string.rep(empty, slots - count), "ProgressTrack" },
  }
end

local function task_text(task)
  local title = vim.trim(inline(task.title))
  local message = vim.trim(inline(task.message))
  local fallback = task.done
      and (task.status == "error" and "Failed" or task.status == "cancelled" and "Cancelled" or "Completed")
    or "Working"
  if task.done and task.status == "success" and message == "Completed" then
    message = ""
  end
  if title == "" or title == "Working" then
    title = message ~= "" and message or fallback
  end
  if message == title then
    message = ""
  end
  return title, message
end

local function task_meta(task, config, now)
  if not task.done and task.percentage ~= nil then
    return ("%d%%"):format(task.percentage)
  end
  if config.show_elapsed and (task.finished or now) - (task.started or now) >= 1000 then
    return elapsed(task, now)
  end
  return ""
end

local function progress(tasks, config, maximum, height, minimum, now)
  if maximum < 4 or height < 1 or #tasks == 0 then
    return nil
  end
  now = now or model.now()
  local c, p = config.progress.window, config.progress
  height = math.min(height, c.max_height)
  local width = math.min(maximum, c.max_width)
  local px, py = padding(c, width, height, 1)
  local available = height - py * 2
  local groups, lookup = {}, {}
  local frames = p.spinner
  local frame = frames[math.floor(now / p.interval) % #frames + 1]
  local shared = package.loaded["theme_tools.icons"]
  local mode = shared and shared.current()
  local icon_width = mode == "none" and 0 or 1
  for _, name in ipairs({ "check", "close", "cancelled", "loading" }) do
    local icon = require("notification-tools.icons").get(
      "ui",
      name,
      name == "loading" and frame or name == "check" and "✔" or name == "close" and "✖" or "−"
    )
    icon_width = math.max(icon_width, cells(inline(icon)))
  end
  if mode ~= "ascii" and mode ~= "none" then
    for _, icon in ipairs(frames) do
      icon_width = math.max(icon_width, cells(inline(icon)))
    end
  end
  for _, task in ipairs(tasks) do
    local source = p.group_by_source and inline(task.source) or ""
    if not lookup[source] then
      lookup[source] = { source = source, tasks = {}, completed = {} }
      groups[#groups + 1] = lookup[source]
    end
    local icon = task.done
        and (task.status == "error" and "✖" or task.status == "cancelled" and "−" or "✔")
      or inline(frame)
    if task.done then
      icon = require("notification-tools.icons").get(
        "ui",
        task.status == "error" and "close" or task.status == "cancelled" and "cancelled" or "check",
        icon
      )
    elseif mode == "ascii" or mode == "none" then
      icon = require("notification-tools.icons").get("ui", "loading", icon)
    end
    local title, message = task_text(task)
    local group = lookup[source]
    local duplicates
    -- Group only equivalent successful results from the same producer. Their
    -- individual IDs, lifetimes and history records remain independent.
    local producer = inline(task.source)
    if task.done and task.status == "success" and producer ~= "" then
      group.completed[producer] = group.completed[producer] or {}
      local titles = group.completed[producer]
      titles[title] = titles[title] or {}
      duplicates = titles[title]
    end
    local entry = duplicates and duplicates[message]
    if entry then
      entry.ids[#entry.ids + 1] = task.id
      entry.meta = ""
      -- Fade the result with the newest member, while older members expire.
      if (task.expires or 0) > (entry.task.expires or 0) then
        entry.task = task
      end
    else
      entry = {
        task = task,
        title = title,
        message = message,
        icon = icon,
        meta = task_meta(task, p, now),
        ids = { task.id },
      }
      group.tasks[#group.tasks + 1] = entry
      if duplicates then
        duplicates[message] = entry
      end
    end
  end
  local total = 0
  for _, group in ipairs(groups) do
    total = total + #group.tasks
  end
  local count = math.min(total, p.max_items, available)
  if total > count and available > 1 then
    count = math.min(count, available - 1)
  end
  local natural = c.min_width - c.padding.horizontal * 2
  local selected, displayed, task_ids = 0, 0, {}
  local selected_groups = {}
  for _, group in ipairs(groups) do
    local entries = {}
    for _, entry in ipairs(group.tasks) do
      if selected >= count then
        break
      end
      selected = selected + 1
      displayed = displayed + #entry.ids
      for _, id in ipairs(entry.ids) do
        task_ids[id] = true
      end
      if #entry.ids > 1 then
        entry.title = entry.title .. " ×" .. #entry.ids
      end
      entries[#entries + 1] = entry
      natural = math.max(
        natural,
        cells(group.source),
        icon_width
          + 1
          + cells(entry.title)
          + (entry.meta ~= "" and math.max(6, cells(entry.meta)) + 2 or 0),
        entry.message ~= "" and icon_width + 1 + cells(entry.message) or 0
      )
    end
    if #entries > 0 then
      group.tasks = entries
      selected_groups[#selected_groups + 1] = group
    end
  end
  groups = selected_groups
  width = width_for(c, maximum, minimum, natural + c.padding.horizontal * 2)
  px, py = padding(c, width, height, 1)
  local inner = width - px * 2
  local function rows(details, gaps, headers, bars)
    local result = {}
    for i, group in ipairs(groups) do
      if gaps and i > 1 then
        result[#result + 1] = { chunks = {} }
      end
      if headers and group.source ~= "" then
        result[#result + 1] = { chunks = { { M.clip(group.source, inner), "Source" } } }
      end
      for _, entry in ipairs(group.tasks) do
        local task = entry.task
        local icon = M.clip(entry.icon, math.max(1, math.min(icon_width, inner - 2)))
        local prefix = icon_width > 0
            and (icon .. string.rep(" ", math.max(1, icon_width - cells(icon) + 1)))
          or ""
        if cells(prefix) >= inner then
          prefix = M.clip(prefix, inner - 1)
        end
        local meta = entry.meta
        local reserved = meta ~= "" and math.max(6, cells(meta)) + 2 or 0
        if inner - cells(prefix) - reserved < 2 then
          meta, reserved = "", 0
        end
        local title = M.clip(entry.title, inner - cells(prefix) - reserved)
        result[#result + 1] = {
          item = task,
          chunks = {
            { prefix, status(task) },
            { title, "TaskTitle" },
            { string.rep(" ", math.max(0, inner - cells(prefix .. title .. meta))) },
            { meta, "Meta" },
          },
        }
        if bars and not task.done and task.percentage ~= nil then
          local indent = math.min(icon_width > 0 and icon_width + 1 or 0, inner - 1)
          local chunks = bar(task, inner - indent)
          if chunks then
            result[#result + 1] = {
              item = task,
              bar = true,
              chunks = vim.list_extend({ { string.rep(" ", indent) } }, chunks),
            }
          end
        end
        if details and entry.message ~= "" then
          local indent = math.min(icon_width > 0 and icon_width + 1 or 0, inner - 1)
          result[#result + 1] = {
            item = task,
            chunks = {
              { string.rep(" ", indent) },
              {
                M.clip(entry.message, inner - indent),
                task.status == "error" and "ERROR" or "Meta",
              },
            },
          }
        end
      end
    end
    if displayed < #tasks and available > 1 then
      result[#result + 1] =
        { chunks = { { M.clip("… +" .. (#tasks - displayed) .. " tasks", inner), "Meta" } } }
    end
    return result
  end
  local bars = p.style == "bar"
  local content = rows(true, true, true, bars)
  if #content > available then
    content = rows(true, false, true, bars)
  end
  if #content > available then
    content = rows(true, false, true, false)
  end
  if #content > available then
    content = rows(false, false, true, false)
  end
  if #content > available then
    content = rows(false, false, false, false)
  end
  local result = panel(width, px)
  for _ = 1, py do
    blank(result)
  end
  result.bar_tasks = {}
  for _, row in ipairs(content) do
    append(result, row.chunks, row.item)
    if row.bar then
      result.bar_tasks[row.item.id] = true
    end
  end
  for _ = 1, py do
    blank(result)
  end
  result.displayed = displayed
  result.task_ids = task_ids
  return result
end

function M.progress(tasks, config, maximum, height, minimum, now)
  now = now or model.now()
  local p = config.progress
  local shared = package.loaded["theme_tools.icons"]
  local key =
    { maximum, height, minimum or 0, text.metrics(), #tasks, shared and shared.current() or false }
  for _, name in ipairs({ "check", "close", "cancelled", "loading" }) do
    key[#key + 1] = require("notification-tools.icons").get("ui", name, "")
  end
  for _, task in ipairs(tasks) do
    key[#key + 1] = {
      task,
      task.title,
      task.message,
      task.source,
      task.done or false,
      task.status or false,
      task.percentage or false,
      not task.done and p.spinner[math.floor(now / p.interval) % #p.spinner + 1] or "",
      task_meta(task, p, now),
    }
  end
  local cached = progress_plans[config]
  if cached and vim.deep_equal(cached.key, key) then
    return cached.plan
  end
  local plan = progress(tasks, config, maximum, height, minimum, now)
  progress_plans[config] = { key = key, plan = plan }
  return plan
end

function M.reset()
  text_cache = setmetatable({}, { __mode = "k" })
  shared_cache = setmetatable({}, { __mode = "k" })
  plans = setmetatable({}, { __mode = "k" })
  progress_plans = setmetatable({}, { __mode = "k" })
end

return M
