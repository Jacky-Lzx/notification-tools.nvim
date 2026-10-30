local M = {}
vim.opt.runtimepath:prepend(vim.fn.getcwd())

function M.eq(expected, actual)
  assert(
    vim.deep_equal(expected, actual),
    "Expected " .. vim.inspect(expected) .. ", got " .. vim.inspect(actual)
  )
end

function M.wait(predicate, timeout)
  assert(vim.wait(timeout or 600, predicate, 10), "Timed out waiting for condition")
end

function M.floats()
  local result = {}
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.bo[buf].filetype == "notification-tools" then
      result[#result + 1] = {
        win = win,
        buf = buf,
        config = vim.api.nvim_win_get_config(win),
        lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false),
      }
    end
  end
  return result
end

return M
