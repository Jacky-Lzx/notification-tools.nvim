-- Only non-interactive messages belong here. The attaching consumer owns
-- cmdline, prompts, showmode/showcmd/ruler and completion UI for the whole lease.
local M = {}
local model = require("notification-tools.state")
local session
local ignored = false
local prompts = { confirm = true, confirm_sub = true, number_prompt = true, return_prompt = true }
local errors = { emsg = true, echoerr = true, lua_error = true, rpc_error = true }

local function interactive(kind)
  -- Old numbered-choice prompts have no kind; their UI flush runs in r/rm.
  return prompts[kind]
    or (kind == "" and not vim.in_fast_event() and vim.fn.mode(1):sub(1, 1) == "r")
end

local function text(chunks)
  local parts, spans, offset = {}, {}, 0
  for _, chunk in ipairs(chunks or {}) do
    parts[#parts + 1] = chunk[2]
    -- Neovim 0.12 supplies a semantic highlight-group ID separately from the
    -- screen attribute ID. Older protocols have no safe attr-to-group mapping.
    if chunk[3] and chunk[3] > 0 and #chunk[2] > 0 then
      local ok, group = pcall(vim.fn.synIDattr, chunk[3], "name")
      if ok and group ~= "" then
        spans[#spans + 1] = { start = offset, finish = offset + #chunk[2], hl_group = group }
      end
    end
    offset = offset + #chunk[2]
  end
  return table.concat(parts), #spans > 0 and spans or nil
end

local function append(previous, content, spans)
  local ranges = vim.deepcopy(previous.spans or {})
  for _, span in ipairs(spans or {}) do
    span.start, span.finish = span.start + #previous.message, span.finish + #previous.message
    ranges[#ranges + 1] = span
  end
  return previous.message .. content, #ranges > 0 and ranges or nil
end

local function level(kind)
  return errors[kind] and vim.log.levels.ERROR
    or kind == "wmsg" and vim.log.levels.WARN
    or vim.log.levels.INFO
end

local function title(kind)
  return kind ~= "" and ("Neovim: " .. kind) or "Neovim"
end

local function reset(s)
  s.last, s.ids, s.order = nil, {}, {}
end

local function history(entries)
  local records = {}
  for _, entry in ipairs(entries) do
    local kind, continuation = entry[1], entry[3]
    local content, spans = text(entry[2])
    if continuation and #records > 0 then
      local previous = records[#records]
      previous.message, previous.spans = append(previous, content, spans)
    else
      records[#records + 1] = {
        id = model.id(),
        kind = "notification",
        message = content,
        level = level(kind),
        title = title(kind),
        source = "neovim",
        details = "",
        markdown = false,
        spans = spans,
        count = 1,
        time = os.time(), -- The native history protocol has no timestamps.
        order = #records + 1,
        timeout = 0,
        display = false,
      }
    end
  end
  return records
end

local function show(s, args)
  local kind, chunks, replace, _, continuation, native_id = unpack(args)
  local content, spans = text(chunks)
  -- Zero is the native unassigned ID, including on versions predating IDs.
  local keyed = native_id ~= nil and native_id ~= 0
  local previous = keyed and s.ids[native_id] or nil
  if not previous and (replace or continuation) then
    previous = s.last
  end
  if continuation and previous then
    content, spans = append(previous, content, spans)
  end
  local item = previous or { id = model.id() }
  item.message, item.spans = content, spans
  s.last = item
  if keyed then
    if not s.ids[native_id] then
      s.order[#s.order + 1] = native_id
      if #s.order > s.config.max_pending then
        s.ids[table.remove(s.order, 1)] = nil
      end
    end
    s.ids[native_id] = item
  end
  local route = s.config.messages.routes[kind] or "show"
  if content == "" then
    return
  end
  s.notify(content, level(kind), {
    id = item.id,
    title = title(kind),
    source = "neovim",
    markdown = false,
    spans = spans,
  }, route)
end

local function drain(s)
  if session ~= s then
    return
  end
  local queue = s.queue
  s.queue, s.pending = {}, false
  if s.overflow then
    reset(s)
    s.overflow = false
  end
  for _, event in ipairs(queue) do
    if session ~= s then
      return
    end
    if event.name == "msg_clear" then
      -- Cards keep their own lifetime; subsequent append/replace starts afresh.
      reset(s)
    elseif event.name == "msg_history_show" then
      s.show_history(history(event.args[1]))
    else
      show(s, event.args)
    end
  end
end

function M.active()
  return session ~= nil
end

-- Keep diagnostics from a failed notification filter out of its own input.
function M.ignore(callback)
  local before = ignored
  ignored = true
  local ok, err = pcall(callback)
  ignored = before
  if not ok then
    error(err)
  end
end

function M.detach()
  local s = session
  if not s then
    return
  end
  session = nil
  vim.ui_detach(s.namespace)
  s.queue = {}
  reset(s)
  if s.changed_cmdheight and vim.o.cmdheight == 0 then
    vim.o.cmdheight = s.cmdheight
  end
end

function M.attach(config, notify, show_history)
  assert(not session, "messages already attached; detach the previous handle first")
  local s = {
    namespace = vim.api.nvim_create_namespace("notification-tools.messages"),
    config = config,
    notify = notify,
    show_history = show_history,
    cmdheight = vim.o.cmdheight,
    queue = {},
  }
  reset(s)
  session = s
  local ok, err = pcall(vim.ui_attach, s.namespace, { ext_messages = true }, function(event, ...)
    if session ~= s or ignored then
      return
    end
    local args = { ... }
    if event == "msg_show" then
      if interactive(args[1]) then
        return -- Never swallow a prompt, insert input, or dismiss a dialog.
      end
    elseif event ~= "msg_clear" and event ~= "msg_history_show" then
      return -- In particular, do not consume cmdline_* or other msg_* widgets.
    end
    if #s.queue >= config.max_pending then
      table.remove(s.queue, 1)
      s.overflow = true
    end
    s.queue[#s.queue + 1] = { name = event, args = args }
    if not s.pending then
      s.pending = true
      vim.schedule(function()
        drain(s)
      end)
    end
    return true
  end)
  if not ok then
    session = nil
    error(err)
  end
  s.changed_cmdheight = s.cmdheight ~= 0 and vim.o.cmdheight == 0
  local handle = {}
  function handle:is_active()
    return session == s
  end
  function handle:detach()
    if session == s then
      M.detach()
    end
  end
  return handle
end

return M
