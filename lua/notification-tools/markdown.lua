-- A small inline renderer for notifications, not a full Markdown document engine.
-- Keep source text in the model; chunks contain only the visible text and styles.
local M = {}

local function push(chunks, text, group, style)
  if text == "" then
    return
  end
  local last = chunks[#chunks]
  if last and last[2] == group and last[3] == style then
    last[1] = last[1] .. text
  else
    chunks[#chunks + 1] = { text, group, style }
  end
end

function M.text(chunks)
  local parts = {}
  for _, chunk in ipairs(chunks) do
    parts[#parts + 1] = chunk[1]
  end
  return table.concat(parts)
end

local function run(text, position, character)
  local finish = position
  while text:sub(finish, finish) == character do
    finish = finish + 1
  end
  return finish - position
end

local function code_end(text, position, count, work)
  local i = position + count
  while i <= #text do
    if work.remaining <= 0 then
      return
    end
    local found = text:find("`", i, true)
    if not found then
      work.remaining = work.remaining - (#text - i + 1)
      return
    end
    local size = run(text, found, "`")
    work.remaining = work.remaining - (found - i + size)
    if size == count then
      return found
    end
    i = found + size
  end
end

local function neighbour(text, position, before)
  if position < 1 or position > #text then
    return ""
  end
  if before then
    local last = position
    while position > 1 and text:byte(position) >= 128 and text:byte(position) < 192 do
      position = position - 1
    end
    return text:sub(position, last)
  end
  local byte = text:byte(position)
  local size = byte < 128 and 1 or byte < 224 and 2 or byte < 240 and 3 or 4
  return text:sub(position, position + size - 1)
end

local function flanking(text, position, count, marker)
  local previous = neighbour(text, position - 1, true)
  local following = neighbour(text, position + count, false)
  local prev_class, next_class = vim.fn.charclass(previous), vim.fn.charclass(following)
  local prev_space = previous == "" or previous:match("%s") ~= nil or prev_class == 0
  local next_space = following == "" or following:match("%s") ~= nil or next_class == 0
  local prev_punct = previous:match("%p") ~= nil or prev_class == 1
  local next_punct = following:match("%p") ~= nil or next_class == 1
  local left = not next_space and (not next_punct or prev_space or prev_punct)
  local right = not prev_space and (not prev_punct or next_space or next_punct)
  if marker == "_" then
    return left and (not right or prev_punct), right and (not left or next_punct)
  end
  return left, right
end

local function link_end(text, position, work)
  local depth, i = 1, position + 1
  while i <= #text and work.remaining > 0 do
    work.remaining = work.remaining - 1
    local char = text:sub(i, i)
    if char == "\\" then
      i = i + 2
    elseif char == "`" then
      local count = run(text, i, "`")
      local finish = code_end(text, i, count, work)
      i = finish and (finish + count) or (i + count)
    else
      if char == "[" then
        depth = depth + 1
      end
      if char == "]" then
        depth = depth - 1
      end
      if depth == 0 then
        break
      end
      i = i + 1
    end
  end
  if depth ~= 0 or text:sub(i + 1, i + 1) ~= "(" then
    return
  end
  local label_end, target_start = i, i + 2
  depth, i = 1, target_start
  while i <= #text and work.remaining > 0 do
    work.remaining = work.remaining - 1
    local char = text:sub(i, i)
    if char == "\\" then
      i = i + 2
    else
      if char == "(" then
        depth = depth + 1
      end
      if char == ")" then
        depth = depth - 1
      end
      if depth == 0 then
        if i > target_start then
          return label_end, i
        end
        return
      end
      i = i + 1
    end
  end
end

local inline
inline = function(text, base, depth, work)
  if depth > 8 then
    return { { text, base } }
  end
  local tokens, start, i = {}, 1, 1
  local function literal(finish)
    if finish >= start then
      tokens[#tokens + 1] = { text = text:sub(start, finish), group = base }
    end
  end
  while i <= #text do
    if work.remaining <= 0 then
      break
    end
    local char, next_position = text:sub(i, i)
    local token
    if char == "\\" and text:sub(i + 1, i + 1):match("%p") then
      token, next_position = { text = text:sub(i + 1, i + 1), group = base }, i + 2
    elseif char == "`" then
      local count = run(text, i, char)
      local finish = code_end(text, i, count, work)
      if finish then
        local code = text:sub(i + count, finish - 1)
        if code:sub(1, 1) == " " and code:sub(-1) == " " and code:find("[^ ]") then
          code = code:sub(2, -2)
        end
        token, next_position = { text = code, group = "MarkdownCode" }, finish + count
      else
        -- Unmatched runs stay literal and must not be reconsidered one tick at a time.
        token, next_position = { text = string.rep(char, count), group = base }, i + count
      end
    elseif char == "[" and text:sub(i - 1, i - 1) ~= "!" then
      local label_end, finish = link_end(text, i, work)
      if label_end and label_end > i + 1 then
        token =
          { children = inline(text:sub(i + 1, label_end - 1), "MarkdownLink", depth + 1, work) }
        next_position = finish + 1
      end
    elseif char == "*" or char == "_" or char == "~" then
      local count = run(text, i, char)
      if char ~= "~" or count == 2 then
        local open, close = flanking(text, i, count, char)
        token = {
          marker = char,
          count = count,
          remaining = count,
          open = open,
          close = close,
          group = base,
        }
        next_position = i + count
      else
        token, next_position = { text = string.rep(char, count), group = base }, i + count
      end
    end
    if token then
      literal(i - 1)
      tokens[#tokens + 1] = token
      i, start = next_position, next_position
    else
      i = i + 1
    end
  end
  literal(#text)
  local stacks, changes = { ["*"] = {}, ["_"] = {}, ["~"] = {} }, {}
  local function change(position, style, amount)
    changes[position] = changes[position] or {}
    changes[position][style] = (changes[position][style] or 0) + amount
  end
  local budget = #text * 8
  for index, token in ipairs(tokens) do
    if token.marker then
      local stack = stacks[token.marker]
      while token.close and token.remaining > 0 and #stack > 0 and budget > 0 do
        local matched = false
        for j = #stack, 1, -1 do
          budget = budget - 1
          local opening = tokens[stack[j]]
          local odd = token.marker ~= "~"
            and (opening.close or token.open)
            and (opening.count + token.count) % 3 == 0
            and (opening.count % 3 ~= 0 or token.count % 3 ~= 0)
          if opening.remaining > 0 and not odd then
            local size = opening.remaining >= 2 and token.remaining >= 2 and 2 or 1
            local style = token.marker == "~" and "Strike" or size == 2 and "Bold" or "Italic"
            change(stack[j] + 1, style, 1)
            change(index, style, -1)
            opening.remaining, token.remaining = opening.remaining - size, token.remaining - size
            if opening.remaining == 0 then
              table.remove(stack, j)
            end
            matched = true
            break
          end
          if budget <= 0 then
            break
          end
        end
        if not matched then
          break
        end
      end
      if token.open and token.remaining > 0 then
        stack[#stack + 1] = index
      end
    end
  end
  local chunks, active = {}, { Bold = 0, Italic = 0, Strike = 0 }
  for index, token in ipairs(tokens) do
    for name, amount in pairs(changes[index] or {}) do
      active[name] = active[name] + amount
    end
    local style = (active.Bold > 0 and "Bold" or "")
      .. (active.Italic > 0 and "Italic" or "")
      .. (active.Strike > 0 and "Strike" or "")
    style = style ~= "" and style or nil
    if token.children then
      for _, child in ipairs(token.children) do
        local combined = ""
        for _, name in ipairs({ "Bold", "Italic", "Strike" }) do
          if active[name] > 0 or (child[3] and child[3]:find(name, 1, true)) then
            combined = combined .. name
          end
        end
        push(chunks, child[1], child[2], combined ~= "" and combined or nil)
      end
    else
      push(
        chunks,
        token.marker and string.rep(token.marker, token.remaining) or token.text,
        token.group,
        style
      )
    end
  end
  return chunks
end

function M.parse(text, base, enabled)
  base = base or "Body"
  if enabled == false then
    return { { text, base } }
  end
  local chunks, fence, fence_size = {}, nil, nil
  local work = { remaining = math.max(256, #text * 8) }
  for index, line in ipairs(vim.split(text, "\n", { plain = true })) do
    if index > 1 then
      push(chunks, "\n", base)
    end
    local marker = line:match("^ ? ? ?(```+)") or line:match("^ ? ? ?(~~~+)")
    if fence then
      push(chunks, line, base)
      if
        marker
        and marker:sub(1, 1) == fence
        and #marker >= fence_size
        and line:match("^%s*" .. marker .. "%s*$")
      then
        fence, fence_size = nil, nil
      end
    elseif marker then
      fence, fence_size = marker:sub(1, 1), #marker
      push(chunks, line, base)
    else
      for _, chunk in ipairs(inline(line, base, 0, work)) do
        push(chunks, chunk[1], chunk[2], chunk[3])
      end
    end
  end
  return chunks
end

function M.wrap(chunks, width, limit)
  local lines, line, visible = {}, {}, ""
  local function flush()
    lines[#lines + 1], line, visible = line, {}, ""
    return limit and #lines >= limit
  end
  for _, chunk in ipairs(chunks) do
    for _, char in ipairs(vim.fn.split(chunk[1], "\\zs")) do
      if char == "\n" then
        if flush() then
          return lines
        end
      else
        if vim.fn.strdisplaywidth(visible .. char) > width then
          if visible ~= "" and flush() then
            return lines
          end
          if vim.fn.strdisplaywidth(char) > width then
            char = "?"
          end
        end
        push(line, char, chunk[2], chunk[3])
        visible = visible .. char
      end
    end
  end
  flush()
  return lines
end

function M.clip(chunks, width, base)
  if width <= 0 then
    return {}
  end
  local lines = M.wrap(chunks, width, 2)
  if #lines == 1 then
    return lines[1]
  end
  local ellipsis = vim.fn.strdisplaywidth("…") <= width and "…" or "."
  local remaining = width - vim.fn.strdisplaywidth(ellipsis)
  local result = remaining > 0 and M.wrap(lines[1], remaining, 1)[1] or {}
  push(result, ellipsis, base or "Body")
  return result
end

return M
