-- Lexical coloring also accepts vim.inspect's non-Lua <function>/<table> tags.
-- Never evaluate the message or require a parser to display a table.
local M = {}
local keywords = {}
for word in
  ("and break do else elseif end for function goto if in local not or repeat return then until while"):gmatch(
    "%S+"
  )
do
  keywords[word] = true
end

local function long_end(value, start)
  local _, opening, equals = value:find("^%[(=*)%[", start)
  if opening then
    local _, closing = value:find("]" .. equals .. "]", opening + 1, true)
    return closing or #value
  end
end

local function number_end(value, start)
  local _, finish = value:find("^0[xX][%da-fA-F]+", start)
  local hex = finish ~= nil
  if not finish then
    finish = select(2, value:find("^%d+", start))
  end
  local _, fraction = value:find(hex and "^%.[%da-fA-F]*" or "^%.%d*", (finish or (start - 1)) + 1)
  finish = fraction or finish
  local _, exponent = value:find(hex and "^[pP][+-]?%d+" or "^[eE][+-]?%d+", finish + 1)
  return exponent or finish
end

function M.parse(value, base, source)
  base = base or "Body"
  local chunks, spans = {}, source and {} or nil
  local row, col = 0, 0
  local function push(start, finish, group)
    local token = value:sub(start, finish)
    chunks[#chunks + 1] = { token, group }
    if spans then
      local offset = 1
      while offset <= #token do
        local newline = token:find("\n", offset, true)
        local size = (newline or (#token + 1)) - offset
        if size > 0 then
          spans[#spans + 1] = { row = row, col = col, finish = col + size, hl = group }
        end
        col = col + size
        if not newline then
          break
        end
        row, col, offset = row + 1, 0, newline + 1
      end
    end
  end
  local i, plain = 1, 1
  while i <= #value do
    local char = value:sub(i, i)
    local finish, group
    if char == '"' or char == "'" then
      finish = i + 1
      while finish <= #value do
        local next_char = value:sub(finish, finish)
        if next_char == "\\" then
          finish = finish + 2
        elseif next_char == char then
          break
        else
          finish = finish + 1
        end
      end
      finish, group = math.min(finish, #value), "LuaString"
    elseif value:sub(i, i + 1) == "--" then
      finish = long_end(value, i + 2) or ((value:find("\n", i + 2, true) or (#value + 1)) - 1)
      group = "LuaComment"
    elseif char == "[" then
      finish = long_end(value, i)
      group = finish and "LuaString" or nil
    elseif char == "<" then
      -- Inspect tags include object identities, cycle references and metatables.
      finish = select(2, value:find("^<[%w_][^<>\n]*>", i))
      group = finish and "LuaSpecial" or nil
    elseif char:match("[%a_]") then
      finish = select(2, value:find("^[%w_]+", i))
      local word = value:sub(i, finish)
      group = (value:find("^%s*=", finish + 1) and "LuaField")
        or ((word == "true" or word == "false") and "LuaBoolean")
        or (word == "nil" and "LuaSpecial")
        or ((word == "inf" or word == "nan") and "LuaNumber")
        or (keywords[word] and "LuaKeyword")
        or base
    elseif char:match("%d") or (char == "." and value:sub(i + 1, i + 1):match("%d")) then
      finish, group = number_end(value, i), "LuaNumber"
    end
    if not finish and char:match("[{}%[%](),;]") then
      finish, group = i, "LuaPunctuation"
    elseif not finish and char:match("[=+*/%%^#<>~:.-]") then
      finish, group = i, "LuaOperator"
    end
    if finish then
      if plain < i then
        push(plain, i - 1, base)
      end
      push(i, finish, group)
      i, plain = finish + 1, finish + 1
    else
      i = i + 1
    end
  end
  if plain <= #value then
    push(plain, #value, base)
  end
  return chunks, spans
end

return M
