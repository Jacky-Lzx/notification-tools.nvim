local M = {}

function M.clean(text)
  return tostring(text or ""):gsub("\t", "  "):gsub("[%z\1-\8\11-\31\127]", "")
end

-- Let Neovim segment graphemes, but never split a whole log for a small preview.
-- Withhold the last grapheme of each batch: it may join the next codepoint.
function M.chars(text)
  local position, batch, index = 1, {}, 1
  return function()
    if index > #batch then
      if position > #text then
        return nil
      end
      local size = 1024
      while true do
        local finish = math.min(#text, position + size - 1)
        while finish < #text and text:byte(finish + 1) >= 128 and text:byte(finish + 1) < 192 do
          finish = finish + 1
        end
        batch = vim.fn.split(text:sub(position, finish), "\\zs")
        if finish < #text then
          local tail = table.remove(batch)
          finish = finish - #tail
        end
        if #batch > 0 or finish == #text then
          position, index = finish + 1, 1
          break
        end
        size = size * 2
      end
    end
    local char = batch[index]
    index = index + 1
    return char
  end
end

function M.metrics()
  return vim.o.ambiwidth .. tostring(vim.o.emoji) .. vim.inspect(vim.fn.getcellwidths())
end

-- Natural width only matters up to the available width. Preserve grapheme width
-- semantics by asking Neovim about the bounded prefix, including combining marks.
function M.width(chunks, maximum)
  local natural, line = 0, ""
  for _, chunk in ipairs(chunks) do
    for char in M.chars(chunk[1]) do
      if char == "\n" then
        line = ""
      else
        line = line .. char
        natural = math.max(natural, vim.fn.strdisplaywidth(line))
        if natural >= maximum then
          return maximum
        end
      end
    end
  end
  return natural
end

return M
