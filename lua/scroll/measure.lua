--- Turning a window into the three numbers `geometry.thumb` needs.
---
--- The vertical case is the performance-critical one. `nvim_win_text_height`
--- is the only call that correctly accounts for folds, wrapping, virtual lines,
--- diff filler and 'smoothscroll', but measuring from the start of the buffer
--- is O(topline): 69ms at line 190000 of a wrapped 200k-line buffer. Calling
--- that on every scroll event is not viable.
---
--- The way out is an additivity identity of `nvim_win_text_height`, verified on
--- this machine:
---
---   A(t) := text_height{start_row = 0, end_row = t - 1, end_vcol = 0}.all
---   A(t1) = A(t0) + text_height{start_row = t0 - 1, start_vcol = 0,
---                               end_row   = t1 - 1, end_vcol   = 0}.all
---
--- `start_vcol = 0` excludes the virtual-line fill above `start_row`, which is
--- exactly what makes the ranges telescope instead of double-counting. So we
--- anchor A once and then move it by the distance actually scrolled, which is
--- O(lines crossed) rather than O(lines above). Scrolling a line costs ~1us
--- instead of 69ms.
local config = require("scroll.config")

local M = {}

--- @type table<integer, { key: string, total: integer, topline: integer, above: integer }>
local cache = {}

--- Everything that can change a buffer's rendered height without it being
--- scrolled. When any of these differ, the anchor and total are stale.
local function cache_key(win, buf)
  local wo = vim.wo[win]
  return table.concat({
    buf,
    vim.api.nvim_buf_get_changedtick(buf),
    vim.api.nvim_win_get_width(win),
    tostring(wo.wrap),
    tostring(wo.diff),
    tostring(wo.list),
    tostring(wo.breakindent),
    tostring(wo.foldenable),
    wo.foldmethod,
    wo.foldlevel,
    vim.bo[buf].tabstop,
  }, ":")
end

--- Screen rows strictly above line `t` (1-based), excluding any virtual-line
--- fill attached above it. Cost is O(t).
local function absolute(win, t)
  if t <= 1 then
    return 0
  end
  return vim.api.nvim_win_text_height(win, { start_row = 0, end_row = t - 1, end_vcol = 0 }).all
end

--- Signed screen-row distance between two toplines. Cost is O(|t1 - t0|).
local function delta(win, t0, t1)
  if t0 == t1 then
    return 0
  end
  local lo, hi, sign = t0, t1, 1
  if t0 > t1 then
    lo, hi, sign = t1, t0, -1
  end
  local d = vim.api.nvim_win_text_height(win, {
    start_row = lo - 1,
    start_vcol = 0,
    end_row = hi - 1,
    end_vcol = 0,
  }).all
  return sign * d
end

--- Rows of the topline itself that 'smoothscroll' has already scrolled past.
--- O(1): the range is a single line.
local function head_rows(win, topline, skipcol)
  if not skipcol or skipcol == 0 then
    return 0
  end
  return vim.api.nvim_win_text_height(win, {
    start_row = topline - 1,
    end_row = topline - 1,
    end_vcol = skipcol,
  }).all
end

--- Screen rows scrolled off above the top of the text area.
---
--- Three strategies, cheapest first:
---   1. When the buffer renders one screen row per line, `total == line_count`
---      and the answer is just `topline - 1` -- no API call at all. The
---      equality makes this self-validating: we never assume there are no
---      folds or wrapping, we observe it.
---   2. Otherwise telescope from the cached anchor, which is exact and costs
---      only the distance scrolled.
---   3. A jump longer than `exact_measure_max_lines` (`gg` to `G` on a huge
---      wrapped buffer) would make even the delta expensive, so that one frame
---      is interpolated and the anchor is re-established from it.
local function rows_above(win, buf, entry, view, total)
  local topline = view.topline
  if topline <= 1 then
    entry.topline, entry.above = 1, 0
    return 0
  end

  local line_count = vim.api.nvim_buf_line_count(buf)
  if total == line_count then
    entry.topline, entry.above = topline, topline - 1
    return topline - 1
  end

  local limit = config.options.exact_measure_max_lines
  local anchored = entry.above ~= nil and entry.topline ~= nil

  if anchored and math.abs(topline - entry.topline) <= limit then
    entry.above = entry.above + delta(win, entry.topline, topline)
  elseif topline <= limit then
    entry.above = absolute(win, topline)
  else
    -- Too far to measure this frame; interpolate and re-anchor from here.
    entry.above = math.floor((topline - 1) / line_count * total + 0.5)
  end
  entry.topline = topline

  return entry.above
end

--- @param win integer
--- @return table|nil  `{ total, offset, page }` for the vertical bar
function M.vertical(win)
  local buf = vim.api.nvim_win_get_buf(win)

  -- `getwininfo().height` is the text height; `nvim_win_get_height` includes
  -- the 'winbar' row, which is not part of the scrollable area.
  local info = vim.fn.getwininfo(win)[1]
  local page = info and info.height or 0
  if page < 1 then
    return nil
  end

  local key = cache_key(win, buf)
  local entry = cache[win]
  if not entry or entry.key ~= key then
    -- Anything that changes rendered height invalidates both the total and
    -- the anchor the telescoping walks from.
    entry = { key = key, total = vim.api.nvim_win_text_height(win, {}).all }
    cache[win] = entry
  end

  local view = vim.api.nvim_win_call(win, vim.fn.winsaveview)
  local above = rows_above(win, buf, entry, view, entry.total)

  -- Add back the part of the topline scrolled past by 'smoothscroll', and drop
  -- the diff filler rows that are actually visible below the top edge.
  above = above + head_rows(win, view.topline, view.skipcol) - (view.topfill or 0)

  return { total = entry.total, offset = math.max(0, above), page = page }
end

--- Inverse of the vertical measurement: the topline that puts `target` screen
--- rows above the top edge. Used by click-to-jump and thumb dragging.
--- @param win integer
--- @param target integer
--- @return integer  1-based line number
function M.topline_at(win, target)
  local buf = vim.api.nvim_win_get_buf(win)
  local line_count = vim.api.nvim_buf_line_count(buf)
  local entry = cache[win]
  local total = entry and entry.total or line_count

  -- One row per line: the mapping is the identity.
  if total == line_count then
    return math.max(1, math.min(line_count, target + 1))
  end

  -- Otherwise interpolate. Exact inversion would need a search over
  -- `nvim_win_text_height`, which is not worth the cost on a pointer drag --
  -- the error is at most a few lines and the user is steering visually.
  local line = math.floor(target / math.max(total, 1) * line_count + 0.5) + 1
  return math.max(1, math.min(line_count, line))
end

--- @param win integer
--- @param doc_width integer  widest line in the buffer, in display columns
--- @return table|nil  `{ total, offset, page, textoff }` for the horizontal bar
function M.horizontal(win, doc_width)
  if vim.wo[win].wrap then
    return nil -- wrapped text never scrolls sideways
  end

  local info = vim.fn.getwininfo(win)[1]
  if not info then
    return nil
  end

  -- `textoff` is the gutter (number, sign, fold and statuscolumn); the text
  -- area is what actually scrolls, so it is both the page and the track.
  local page = info.width - info.textoff
  if page < 1 then
    return nil
  end

  return { total = doc_width, offset = info.leftcol, page = page, textoff = info.textoff }
end

--- @param win integer
function M.forget(win)
  cache[win] = nil
end

function M.reset()
  cache = {}
end

return M
