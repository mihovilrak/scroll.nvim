--- Per-buffer cache of the widest line, in display columns.
---
--- This is the horizontal bar's equivalent of "how tall is the document", and
--- it is the one genuinely expensive quantity in the plugin: measuring every
--- line of a 100k-line buffer with `strdisplaywidth` costs ~73ms. So the full
--- scan runs in chunks off a timer, while the visible lines -- always cheap --
--- are measured synchronously so the bar is never blank while a scan is in
--- flight.
local M = {}

--- Lines per chunk. ~2000 lines measures in about 1.5ms, comfortably inside a
--- frame, so typing never stutters behind a scan.
local CHUNK = 2000

--- Buffers at or below this size are scanned in one synchronous pass; the
--- timer machinery would cost more than the measurement.
local SYNC_MAX_LINES = 2000

--- @type table<integer, { width: integer, tick: integer?, timer: userland?, scan_max: integer, row: integer }>
local cache = {}

--- Widest of `lines`, in display columns.
---
--- `strdisplaywidth` reads the *current* buffer's 'tabstop', so the call is
--- wrapped in the owning buffer's context -- otherwise a file with `ts=2` gets
--- measured against whatever buffer happened to be current.
local function widest(buf, lines)
  return vim.api.nvim_buf_call(buf, function()
    local max = 0
    for i = 1, #lines do
      local w = vim.fn.strdisplaywidth(lines[i])
      if w > max then
        max = w
      end
    end
    return max
  end)
end

local function stop_scan(entry)
  if entry.timer then
    entry.timer:stop()
    if not entry.timer:is_closing() then
      entry.timer:close()
    end
    entry.timer = nil
  end
end

--- Walk the buffer in chunks, publishing the result only once the scan
--- completes. Serving the previous value until then keeps the thumb from
--- jittering while the user types.
local function start_scan(buf, entry, on_done)
  stop_scan(entry)
  entry.scan_max = 0
  entry.row = 0

  local line_count = vim.api.nvim_buf_line_count(buf)
  if line_count <= SYNC_MAX_LINES then
    entry.width = widest(buf, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    entry.tick = vim.api.nvim_buf_get_changedtick(buf)
    -- No callback: the caller is inside `get` and will read `entry.width`
    -- as soon as this returns. Invoking it here would re-enter the render
    -- pass that asked for the width in the first place.
    return
  end

  local tick = vim.api.nvim_buf_get_changedtick(buf)
  local timer = vim.uv.new_timer()
  entry.timer = timer
  timer:start(
    0,
    5,
    vim.schedule_wrap(function()
      -- The buffer may have been unloaded or edited out from under the scan.
      if not vim.api.nvim_buf_is_valid(buf) or vim.api.nvim_buf_get_changedtick(buf) ~= tick then
        stop_scan(entry)
        return
      end

      local last = math.min(entry.row + CHUNK, line_count)
      local chunk = vim.api.nvim_buf_get_lines(buf, entry.row, last, false)
      entry.scan_max = math.max(entry.scan_max, widest(buf, chunk))
      entry.row = last

      if entry.row >= line_count then
        stop_scan(entry)
        local changed = entry.width ~= entry.scan_max
        entry.width = entry.scan_max
        entry.tick = tick
        -- Only worth a redraw if the document actually turned out to be a
        -- different width than we had been drawing.
        if on_done and changed then
          vim.schedule(on_done)
        end
      end
    end)
  )
end

--- Widest line in `buf`, in display columns.
---
--- Always at least as wide as the lines currently on screen, so a long line
--- typed right now widens the bar immediately rather than after the next scan.
--- @param buf integer
--- @param win integer  window whose visible range seeds the estimate
--- @param on_update function|nil  called when a background scan finishes
--- @return integer
function M.get(buf, win, on_update)
  local entry = cache[buf]
  if not entry then
    entry = { width = 0, scan_max = 0, row = 0 }
    cache[buf] = entry
  end

  if entry.tick ~= vim.api.nvim_buf_get_changedtick(buf) and not entry.timer then
    start_scan(buf, entry, on_update)
  end

  local info = vim.fn.getwininfo(win)[1]
  local visible = 0
  if info then
    visible = widest(buf, vim.api.nvim_buf_get_lines(buf, info.topline - 1, info.botline, false))
  end

  return math.max(entry.width, visible)
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
end

return M
