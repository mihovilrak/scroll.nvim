--- Per-window refresh: read the window's state, run the geometry, draw the bars.
local Bar = require("scroll.bar")
local config = require("scroll.config")
local geometry = require("scroll.geometry")
local measure = require("scroll.measure")
local ruler = require("scroll.ruler")
local util = require("scroll.util")
local width = require("scroll.width")

local M = {}

--- @type table<integer, { vertical: table?, horizontal: table? }>
local bars = {}

--- Which bar the pointer is currently over, so it can be drawn highlighted.
--- @type { win: integer?, orientation: string? }
M.hover = {}

local function bars_for(win)
  local entry = bars[win]
  if not entry then
    entry = {}
    bars[win] = entry
  end
  return entry
end

--- Geometry for both bars, or nil where that bar should not be shown.
--- Kept separate from drawing so tests can assert placement without floats.
--- @param win integer
--- @return table  `{ info, vertical = {pos,size}?, horizontal = {pos,size,textoff,track}? }`
function M.compute(win)
  local opts = config.options
  local info = vim.fn.getwininfo(win)[1]
  local result = { info = info }
  if not info then
    return result
  end

  if opts.vertical.enabled then
    local m = measure.vertical(win)
    if m then
      local g = geometry.thumb({
        track = info.height,
        total = m.total,
        offset = m.offset,
        page = m.page,
      })
      if g then
        -- Carry the metrics through: the mouse handlers need the same numbers
        -- to invert the geometry, and recomputing them would be both wasteful
        -- and a chance for the two to disagree mid-drag.
        result.vertical = { pos = g.pos, size = g.size, total = m.total, page = m.page }
      end
    end
  end

  if opts.horizontal.enabled then
    local buf = vim.api.nvim_win_get_buf(win)
    local doc_w = width.get(buf, win, function()
      -- A background scan just finished and the document may now be wider
      -- than we thought; redraw so the thumb reflects it.
      M.refresh(win)
    end)
    local m = measure.horizontal(win, doc_w)
    if m then
      -- Leave the bottom-right corner to the vertical bar rather than letting
      -- the two overlap there.
      local track = m.page - (result.vertical and opts.vertical.width or 0)
      local g = geometry.thumb({
        track = track,
        total = m.total,
        offset = m.offset,
        page = m.page,
      })
      if g then
        result.horizontal = {
          pos = g.pos,
          size = g.size,
          textoff = m.textoff,
          track = track,
          total = m.total,
          page = m.page,
        }
      end
    end
  end

  return result
end

--- A source finished work in the background. Redraw the bars that are on
--- screen, without waking hidden ones: an LSP publishing diagnostics while
--- you read should not flash the bars up.
local function marks_updated()
  require("scroll.events").schedule({ quiet = true })
end

--- @param win integer
--- @param entry table  the window's bars
--- @param computed table  from `compute`
--- @param hovered boolean
local function draw_vertical(win, entry, computed, hovered)
  local opts = config.options
  local info, v = computed.info, computed.vertical
  if not v then
    if entry.vertical then
      entry.vertical:hide()
    end
    return
  end

  local marks, marks_sig = ruler.cells(win, info.height, v.total, marks_updated)
  entry.vertical = entry.vertical or Bar.new()
  entry.vertical:update(win, {
    orientation = "vertical",
    row = info.winbar, -- relative='win' row 0 is the winbar row
    col = info.width - opts.vertical.width,
    width = opts.vertical.width,
    height = info.height,
    length = info.height,
    pos = v.pos,
    size = v.size,
    char = opts.vertical.char,
    track_char = opts.vertical.track_char,
    winblend = opts.winblend,
    zindex = opts.zindex,
    hovered = hovered,
    marks = marks,
    marks_sig = marks_sig,
  })
end

--- @param win integer
--- @param entry table  the window's bars
--- @param computed table  from `compute`
--- @param hovered boolean
local function draw_horizontal(win, entry, computed, hovered)
  local opts = config.options
  local info, h = computed.info, computed.horizontal
  if not h then
    if entry.horizontal then
      entry.horizontal:hide()
    end
    return
  end

  entry.horizontal = entry.horizontal or Bar.new()
  entry.horizontal:update(win, {
    orientation = "horizontal",
    row = info.winbar + info.height - opts.horizontal.height,
    col = h.textoff,
    width = h.track,
    height = opts.horizontal.height,
    length = h.track,
    pos = h.pos,
    size = h.size,
    char = opts.horizontal.char,
    track_char = opts.horizontal.track_char,
    winblend = opts.winblend,
    zindex = opts.zindex,
    hovered = hovered,
  })
end

--- @param win integer
--- @param quiet boolean|nil  only redraw bars that are already showing
function M.refresh(win, quiet)
  if not util.is_eligible(win) then
    M.clear(win)
    return
  end

  local entry = bars_for(win)
  -- A quiet refresh leaves hidden (or never drawn) bars alone.
  local skip_vertical = quiet and (not entry.vertical or entry.vertical.hidden)
  local skip_horizontal = quiet and (not entry.horizontal or entry.horizontal.hidden)
  if skip_vertical and skip_horizontal then
    return
  end
  local computed = M.compute(win)
  local info = computed.info
  if not info then
    return
  end

  local hovered_orientation = (M.hover.win == win) and M.hover.orientation or nil

  if not skip_vertical then
    draw_vertical(win, entry, computed, hovered_orientation == "vertical")
  end
  if not skip_horizontal then
    draw_horizontal(win, entry, computed, hovered_orientation == "horizontal")
  end
end

--- Refresh every ordinary window in the current tabpage.
--- @param quiet boolean|nil  only redraw bars that are already showing
function M.refresh_all(quiet)
  for _, win in ipairs(util.target_windows()) do
    M.refresh(win, quiet)
  end
end

--- Hide both bars of `win` without destroying them.
--- @param win integer
function M.hide(win)
  local entry = bars[win]
  if entry then
    if entry.vertical then
      entry.vertical:hide()
    end
    if entry.horizontal then
      entry.horizontal:hide()
    end
  end
end

function M.hide_all()
  for win in pairs(bars) do
    M.hide(win)
  end
end

--- Tear down the bars of a window that is gone or no longer eligible.
--- @param win integer
function M.clear(win)
  local entry = bars[win]
  if entry then
    if entry.vertical then
      entry.vertical:destroy()
    end
    if entry.horizontal then
      entry.horizontal:destroy()
    end
    bars[win] = nil
  end
  measure.forget(win)
  ruler.forget_win(win)
end

function M.clear_all()
  for win in pairs(vim.deepcopy(bars)) do
    M.clear(win)
  end
  bars = {}
end

--- Map a bar's float back to the window it decorates.
--- @param float_win integer
--- @return integer?, string?  parent window and orientation
function M.owner_of(float_win)
  for win, entry in pairs(bars) do
    for orientation, bar in pairs(entry) do
      if bar.win == float_win then
        return win, orientation
      end
    end
  end
  return nil, nil
end

--- Drop bookkeeping for windows that no longer exist.
function M.prune()
  for win in pairs(vim.deepcopy(bars)) do
    if not vim.api.nvim_win_is_valid(win) then
      M.clear(win)
    end
  end
end

return M
