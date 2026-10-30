local M = {}
local model = require("notification-tools.state")
local markdown = require("notification-tools.markdown")
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
  then
    cached = {
      enabled = enabled,
      message = notice.message,
      details = notice.details,
      body = markdown.parse(M.clean(notice.message), "Body", enabled),
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
  local icon = inline(notice.icon or config.icons[level] or "●")
  local title = inline(notice.title)
  local indent_width = cells(icon) + 1
  local meta = (notice.count or 1) > 1 and ("×" .. notice.count)
    or (config.notification.timestamp and os.date("%H:%M", notice.time) or "")
  local natural = cells(icon .. " " .. title) + (meta ~= "" and cells(meta) + 2 or 0)
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
  local chunks = header(icon .. " " .. title, "Title", meta, inner)
  -- Separate the icon's severity from the title's normal emphasis, in byte columns.
  local left = chunks[1][1]
  local visible_icon = M.clip(icon, math.max(1, inner - 1))
  if left:sub(1, #visible_icon) == visible_icon then
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
    notice.icon or false,
    notice.markdown,
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
  local count = math.min(#tasks, p.max_items, available)
  if #tasks > count and available > 1 then
    count = math.min(count, available - 1)
  end
  local groups, lookup = {}, {}
  local frames = p.spinner
  local frame = frames[math.floor(now / p.interval) % #frames + 1]
  local icon_width = math.max(1, cells("✔"), cells("✖"), cells("−"))
  for _, icon in ipairs(frames) do
    icon_width = math.max(icon_width, cells(inline(icon)))
  end
  local natural = c.min_width - c.padding.horizontal * 2
  for i = 1, count do
    local task = tasks[i]
    local source = p.group_by_source and inline(task.source) or ""
    if not lookup[source] then
      lookup[source] = { source = source, tasks = {} }
      groups[#groups + 1] = lookup[source]
    end
    local icon = task.done
        and (task.status == "error" and "✖" or task.status == "cancelled" and "−" or "✔")
      or inline(frame)
    local meta = task.percentage ~= nil and ("%d%%"):format(task.percentage)
      or (p.show_elapsed and elapsed(task, now) or "")
    lookup[source].tasks[#lookup[source].tasks + 1] = { task = task, icon = icon, meta = meta }
    natural = math.max(
      natural,
      cells(source),
      icon_width
        + 1
        + cells(inline(task.title))
        + (meta ~= "" and math.max(6, cells(meta)) + 2 or 0)
    )
    if task.message ~= "" then
      natural = math.max(natural, icon_width + 1 + cells(inline(task.message)))
    end
  end
  width = width_for(c, maximum, minimum, natural + c.padding.horizontal * 2)
  px, py = padding(c, width, height, 1)
  local inner = width - px * 2
  local function rows(details, gaps, headers)
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
        local prefix = icon .. string.rep(" ", math.max(1, icon_width - cells(icon) + 1))
        if cells(prefix) >= inner then
          prefix = M.clip(prefix, inner - 1)
        end
        local meta = entry.meta
        local reserved = meta ~= "" and math.max(6, cells(meta)) + 2 or 0
        if inner - cells(prefix) - reserved < 2 then
          meta, reserved = "", 0
        end
        local title = M.clip(inline(task.title), inner - cells(prefix) - reserved)
        result[#result + 1] = {
          item = task,
          chunks = {
            { prefix, status(task) },
            { title, "TaskTitle" },
            { string.rep(" ", math.max(0, inner - cells(prefix .. title .. meta))) },
            { meta, "Meta" },
          },
        }
        if details and task.message ~= "" then
          local indent = math.min(icon_width + 1, inner - 1)
          result[#result + 1] = {
            item = task,
            chunks = {
              { string.rep(" ", indent) },
              { M.clip(task.message, inner - indent), "Meta" },
            },
          }
        end
      end
    end
    if count < #tasks and available > 1 then
      result[#result + 1] =
        { chunks = { { M.clip("… +" .. (#tasks - count) .. " tasks", inner), "Meta" } } }
    end
    return result
  end
  local content = rows(true, true, true)
  if #content > available then
    content = rows(true, false, true)
  end
  if #content > available then
    content = rows(false, false, true)
  end
  if #content > available then
    content = rows(false, false, false)
  end
  local result = panel(width, px)
  for _ = 1, py do
    blank(result)
  end
  for _, row in ipairs(content) do
    append(result, row.chunks, row.item)
  end
  for _ = 1, py do
    blank(result)
  end
  result.displayed = count
  return result
end

function M.progress(tasks, config, maximum, height, minimum, now)
  now = now or model.now()
  local p = config.progress
  local key = { maximum, height, minimum or 0, text.metrics(), #tasks }
  for i = 1, math.min(#tasks, p.max_items, math.max(0, height)) do
    local task = tasks[i]
    key[#key + 1] = {
      task,
      task.title,
      task.message,
      task.source,
      task.done or false,
      task.status or false,
      task.percentage or false,
      not task.done and p.spinner[math.floor(now / p.interval) % #p.spinner + 1] or "",
      task.percentage == nil and p.show_elapsed and elapsed(task, now) or "",
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
