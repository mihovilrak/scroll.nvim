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

--- @type table<integer, { key: string, total: integer, topline: integer, above: integer, folds: table<integer, integer> }>
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

--- Whether a fold was opened, closed, created or deleted since `entry` was
--- measured. None of those fire an event or touch an option, so the cache key
--- cannot see them. (`zM`/`zR` change 'foldlevel' and are caught by the key.)
---
--- Only the visible lines are walked, O(height), but what each line looked
--- like is remembered across scrolls in `entry.seen`: the last line of its
--- closed fold, or `false` when it was not folded. A line that merely scrolls
--- into view has no record and costs nothing; a line whose fold state
--- disagrees with its record means the folds changed.
local function folds_changed(win, entry, topline, botline)
  local seen = entry.seen
  return vim.api.nvim_win_call(win, function()
    local l = topline
    while l <= botline do
      local state = false
      if vim.fn.foldclosed(l) ~= -1 then
        state = vim.fn.foldclosedend(l)
      end
      if seen[l] == nil then
        seen[l] = state
      elseif seen[l] ~= state then
        return true
      end
      l = state and state + 1 or l + 1
    end
    return false
  end)
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
  local folded = vim.wo[win].foldenable
  if
    not entry
    or entry.key ~= key
    or (folded and folds_changed(win, entry, info.topline, info.botline))
  then
    -- Anything that changes rendered height invalidates both the total and
    -- the anchor the telescoping walks from.
    entry = { key = key, total = vim.api.nvim_win_text_height(win, {}).all, seen = {} }
    cache[win] = entry
    if folded then
      folds_changed(win, entry, info.topline, info.botline) -- record the new state
    end
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

--- Screen rows above each of `lines`, in the same units as `vertical().total`.
--- Used to place overview-ruler marks, which do not move when scrolling, so
--- this runs only when the marks or the document change.
---
--- Same strategy as `rows_above`: identity when the buffer renders one row per
--- line, exact telescoping for buffers up to `exact_measure_max_lines`, and
--- interpolation beyond that. A line past the end maps to `total`.
--- @param win integer
--- @param lines integer[]  1-based, ascending
--- @param total integer
--- @return integer[]
function M.rows_above_lines(win, lines, total)
  local buf = vim.api.nvim_win_get_buf(win)
  local line_count = vim.api.nvim_buf_line_count(buf)
  local out = {}

  if total == line_count or line_count > config.options.exact_measure_max_lines then
    for i, l in ipairs(lines) do
      out[i] = l > line_count and total or math.floor((l - 1) / line_count * total + 0.5)
    end
    return out
  end

  local prev, above = 1, 0
  for i, l in ipairs(lines) do
    if l > line_count then
      out[i] = total
    else
      above = above + delta(win, prev, l)
      prev = l
      out[i] = above
    end
  end
  return out
end

--- Identifies the measurement currently cached for `win`; changes whenever
--- `total` might have.
--- @param win integer
--- @return string
function M.signature(win)
  local entry = cache[win]
  return entry and (entry.key .. ":" .. entry.total) or ""
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
