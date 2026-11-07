-- One content dispatch for wrapped popups and original-source readers.
local M = {}
local clean = require("notification-tools.text").clean

local function parse(value, base, markdown, filetype, source)
  if filetype == "lua" then
    return require("notification-tools.lua").parse(value, base, source)
  end
  if filetype == "text" then
    markdown = false
  end
  return require("notification-tools.markdown").parse(value, base, markdown, source)
end

function M.parse(value, base, markdown, filetype, source, ranges)
  if not ranges or #ranges == 0 then
    return parse(clean(value), base, markdown, filetype, source)
  end
  local chunks, marks = {}, source and {} or nil
  local row, col, offset = 0, 0, 0
  local function append(finish, span)
    local text = clean(value:sub(offset + 1, finish))
    local group = span
        and span.hl_group
        and require("notification-tools.theme").external(span.hl_group)
      or base
    local ft = span and (span.hl_group and "text" or span.filetype) or filetype
    local parts, spans = parse(text, group, markdown, ft, source)
    vim.list_extend(chunks, parts)
    for _, mark in ipairs(spans or {}) do
      if mark.row == 0 then
        mark.col, mark.finish = mark.col + col, mark.finish + col
      end
      mark.row = mark.row + row
      marks[#marks + 1] = mark
    end
    if source then
      local lines = vim.split(text, "\n", { plain = true })
      row = row + #lines - 1
      col = #lines > 1 and #lines[#lines] or (col + #text)
    end
    offset = finish
  end
  for _, span in ipairs(ranges) do
    if offset < span.start then
      append(span.start)
    end
    append(span.finish, span)
  end
  if offset < #value then
    append(#value)
  end
  return chunks, marks
end

function M.source(value, base, markdown, filetype, ranges)
  if ranges and #ranges > 0 then
    local _, marks = M.parse(value, base, markdown, filetype, true, ranges)
    return marks
  end
  value = clean(value)
  if filetype ~= "lua" then
    if filetype == "text" then
      markdown = false
    end
    return require("notification-tools.markdown").source(value, base, markdown)
  end
  local _, spans = M.parse(value, base, markdown, filetype, true)
  return spans
end

return M
