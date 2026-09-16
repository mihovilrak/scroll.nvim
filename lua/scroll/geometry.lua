--- Pure scrollbar math.
---
--- Nothing in here touches the Neovim API, so every function is directly
--- unit-testable without opening a window. Both bars reduce to the same
--- one-dimensional problem, so they share one implementation: the vertical bar
--- measures in screen rows, the horizontal one in screen columns.
local M = {}

local function clamp(value, lo, hi)
  if value < lo then
    return lo
  elseif value > hi then
    return hi
  end
  return value
end

--- Place a thumb on a track.
---
--- @param opts table
---   track    integer  length of the track, in cells
---   total    integer  total extent of the content, in cells
---   offset   integer  content extent scrolled past the start of the track
---   page     integer  content extent visible at once (default: `track`)
---   min_size integer  smallest thumb we are willing to draw (default: 1)
--- @return table|nil  `{ pos, size }` with `pos` a 0-based offset into the
---   track, or nil when the content fits and no bar should be drawn.
function M.thumb(opts)
  local track = opts.track
  local total = opts.total
  local page = opts.page or track
  local min_size = opts.min_size or 1

  -- Nowhere to draw, or nothing to scroll.
  if track < 1 or page < 1 or total <= page then
    return nil
  end

  local size = clamp(math.floor(track * page / total + 0.5), min_size, track)

  -- The thumb can only travel `track - size` cells, and the content can only
  -- scroll `total - page` cells. Scaling between those two ranges (rather than
  -- the naive `offset / total * track`) is what makes the thumb reach the
  -- bottom exactly when the content does, instead of stopping a cell short.
  local offset = clamp(opts.offset, 0, total - page)
  local travel = track - size
  local scrollable = total - page
  local pos = (scrollable > 0) and math.floor(offset * travel / scrollable + 0.5) or 0

  return { pos = clamp(pos, 0, travel), size = size }
end

--- Invert `thumb`: given a position along the track, the content offset that
--- would put the *start* of the thumb there. Used by click-to-jump and drag.
---
--- @param opts table  same shape as `thumb`, with `pos` instead of `offset`
--- @return integer  content offset, clamped to the scrollable range
function M.offset_at(opts)
  local track = opts.track
  local total = opts.total
  local page = opts.page or track
  local min_size = opts.min_size or 1

  if track < 1 or page < 1 or total <= page then
    return 0
  end

  local size = clamp(math.floor(track * page / total + 0.5), min_size, track)
  local travel = track - size
  local scrollable = total - page
  if travel < 1 then
    return 0
  end

  local pos = clamp(opts.pos, 0, travel)
  return clamp(math.floor(pos * scrollable / travel + 0.5), 0, scrollable)
end

return M
