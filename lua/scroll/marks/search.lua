--- Search-match marks for the overview ruler: every line matching `@/`,
--- shown while 'hlsearch' is highlighting it.
---
--- Matching is O(lines), so like `width.lua`, small buffers are scanned
--- synchronously and large ones in chunks off a timer, serving the previous
--- result until a scan finishes.
local M = {}

local CHUNK = 2000
local SYNC_MAX_LINES = 2000

--- @type table<integer, { key: string?, version: integer, ranges: table[], scanning: string?, timer: userdata? }>
local cache = {}
local counter = 0
local last_state = nil

--- The pattern as Nvim would match it. `vim.regex` ignores 'ignorecase', and
--- 'smartcase' applies to `@/` too, so the case rule is made explicit.
local function effective_pattern()
  local pat = vim.fn.getreg("/")
  if pat == "" then
    return nil
  end
  local ignore = vim.o.ignorecase
  if ignore and vim.o.smartcase and pat:gsub("\\.", ""):find("%u") then
    ignore = false
  end
  return (ignore and "\\c" or "\\C") .. pat
end

local function active()
  return vim.v.hlsearch == 1 and vim.o.hlsearch
end

--- Cheap check, run on `SafeState`: did the search pattern or its
--- highlighting change? Neither has an event of its own (`:nohlsearch`, `n`,
--- `*`, a mapping that sets `@/`...).
--- @return boolean
function M.state_changed()
  local state = tostring(active()) .. "\0" .. vim.fn.getreg("/")
  if state == last_state then
    return false
  end
  last_state = state
  return true
end

local function stop_scan(entry)
  if entry.timer then
    entry.timer:stop()
    if not entry.timer:is_closing() then
      entry.timer:close()
    end
    entry.timer = nil
  end
  entry.scanning = nil
end

--- Append the matching lines in `[from, to)` (0-based) to `ranges`, merging
--- runs of consecutive lines into one range.
local function scan(buf, regex, from, to, ranges)
  for row = from, to - 1 do
    if regex:match_line(buf, row) then
      local line = row + 1
      local last = ranges[#ranges]
      if last and last.last == line - 1 then
        last.last = line
      else
        ranges[#ranges + 1] = { first = line, last = line, kind = "search" }
      end
    end
  end
end

local function publish(entry, key, ranges)
  counter = counter + 1
  entry.key, entry.ranges, entry.version = key, ranges, counter
end

--- @param buf integer
--- @param on_update function|nil  called when a background scan finishes
--- @return table[], integer|string
function M.get(buf, on_update)
  if not active() then
    return {}, "off"
  end
  local pat = effective_pattern()
  local ok, regex = pcall(vim.regex, pat or "")
  if not pat or not ok then
    return {}, "off"
  end

  local tick = vim.api.nvim_buf_get_changedtick(buf)
  local key = pat .. "\0" .. tick
  local entry = cache[buf]
  if not entry then
    entry = { version = 0, ranges = {} }
    cache[buf] = entry
  end
  if entry.key == key or entry.scanning == key then
    return entry.ranges, entry.version
  end

  stop_scan(entry)
  local line_count = vim.api.nvim_buf_line_count(buf)
  if line_count <= SYNC_MAX_LINES then
    local ranges = {}
    scan(buf, regex, 0, line_count, ranges)
    publish(entry, key, ranges)
    return entry.ranges, entry.version
  end

  entry.scanning = key
  local ranges, row = {}, 0
  local timer = vim.uv.new_timer()
  entry.timer = timer
  timer:start(
    0,
    5,
    vim.schedule_wrap(function()
      if entry.timer ~= timer then
        return
      end
      if not vim.api.nvim_buf_is_valid(buf) or vim.api.nvim_buf_get_changedtick(buf) ~= tick then
        stop_scan(entry)
        return
      end
      local last = math.min(row + CHUNK, line_count)
      scan(buf, regex, row, last, ranges)
      row = last
      if row >= line_count then
        stop_scan(entry)
        publish(entry, key, ranges)
        if on_update then
          on_update()
        end
      end
    end)
  )
  return entry.ranges, entry.version
end

--- @param buf integer
function M.forget(buf)
  local entry = cache[buf]
  if entry then
    stop_scan(entry)
    cache[buf] = nil
  end
end

function M.reset()
  for buf in pairs(cache) do
    M.forget(buf)
  end
  cache = {}
  last_state = nil
end

return M
