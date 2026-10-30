-- Deliberately small external renderer for UI protocol tests, not a shipped UI.
local M = { events = {} }
local ns = vim.api.nvim_create_namespace("notification-tools.test-cmdline")
local win, buf
local function close()
  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_close(win, true)
  end
  win = nil
end
vim.ui_attach(ns, { ext_cmdline = true }, function(event, ...)
  local args = { ... }
  if event:match("^cmdline_") then
    M.events[#M.events + 1] = event
    if event == "cmdline_show" then
      local chunks, _, firstc, prompt = unpack(args)
      local parts = { firstc ~= "" and firstc or prompt }
      for _, chunk in ipairs(chunks) do
        parts[#parts + 1] = chunk[2]
      end
      if not win then
        buf = vim.api.nvim_create_buf(false, true)
        vim.bo[buf].bufhidden = "wipe"
        win = vim.api.nvim_open_win(buf, false, {
          relative = "editor",
          row = vim.o.lines - 3,
          col = 0,
          width = vim.o.columns - 2,
          height = 1,
          focusable = false,
          style = "minimal",
          border = "single",
        })
      end
      local content = table.concat(parts)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(content, "\n", { plain = true }))
      vim.cmd.redraw()
      if content:find("lease-confirm", 1, true) then
        vim.rpcnotify(1, "notification-tools-test-prompt")
      end
    elseif event == "cmdline_hide" then
      close()
    end
    return true
  end
  if
    event == "msg_show"
    and vim.tbl_contains({ "confirm", "confirm_sub", "number_prompt", "return_prompt" }, args[1])
  then
    M.events[#M.events + 1] = args[1]
    if args[1] == "confirm" then
      vim.rpcnotify(1, "notification-tools-test-prompt")
    elseif args[1] == "return_prompt" then
      -- The external renderer owns the hit-enter policy, as well as drawing.
      vim.api.nvim_input("<CR>")
    end
    return true
  end
end)
function M.stop()
  close()
  vim.ui_detach(ns)
end
return M
