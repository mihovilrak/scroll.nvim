--- Per-window refresh: read the window's state, run the geometry, draw the bars.
local Bar = require("scroll.bar")
local config = require("scroll.config")
local dodge = require("scroll.dodge")
local explorer = require("scroll.explorer")
local geometry = require("scroll.geometry")
local highlight = require("scroll.highlight")
local measure = require("scroll.measure")
local minimap = require("scroll.minimap")
local ruler = require("scroll.ruler")
local util = require("scroll.util")
local width = require("scroll.width")

local M = {}

--- @type table<integer, { vertical: table?, horizontal: table?, minimap: table? }>
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
--- @return table  `{ info, kind, vertical = {pos,size}?, horizontal = {pos,size,textoff,track}?, minimap? }`
function M.compute(win)
  local opts = config.options
  local info = vim.fn.getwininfo(win)[1]
  local kind = util.kind(win)
  local result = { info = info, kind = kind }
  if not info then
    return result
  end

  -- Explorers get the vertical bar only.
  local code = kind == "code"
  result.minimap = code and minimap.compute(win, info) or nil

  if opts.vertical.enabled then
    local m
    if kind == "snacks" then
      m = explorer.measure(win, info.height)
    else
      m = measure.vertical(win)
    end
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

  if opts.horizontal.enabled and code then
    local buf = vim.api.nvim_win_get_buf(win)
    local doc_w = width.get(buf, win, function()
      -- A background scan just finished and the document may now be wider
      -- than we thought; redraw so the thumb reflects it.
      M.refresh(win)
    end)
    local m = measure.horizontal(win, doc_w)
    if m then
      -- Leave the bottom-right corner to the vertical bar (and the minimap)
      -- rather than letting them overlap there.
      local track = m.page - (result.vertical and opts.vertical.width or 0)
      if result.minimap then
        track = math.min(track, result.minimap.col - m.textoff)
      end
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

--- Box-drawing joints for the bottom-right corner, keyed by the vertical then
--- the horizontal track glyph. Other glyph pairs get no joint.
local corners = {
  ["│─"] = "┘",
  ["┃━"] = "┛",
  ["│━"] = "┙",
  ["┃─"] = "┚",
  ["║═"] = "╝",
  ["╎╌"] = "┘",
  ["┆┄"] = "┘",
}

--- The glyph that joins the two tracks where they meet, or nil when they do
--- not meet: no horizontal bar, one ended early by the minimap, or bars
--- thicker than one cell.
--- @param computed table  from `compute`
--- @return string|nil
local function corner(computed)
  local opts = config.options
  local info, h = computed.info, computed.horizontal
  if not h or opts.vertical.width ~= 1 or opts.horizontal.height ~= 1 then
    return nil
  end
  if h.textoff + h.track ~= info.width - 1 then
    return nil
  end
  return corners[opts.vertical.track_char .. opts.horizontal.track_char]
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

  local marks, content_sig = {}, ""
  if computed.kind == "code" then
    marks, content_sig = ruler.cells(win, info.height, v.total, marks_updated)
  end
  local zindex = opts.zindex
  if computed.kind == "snacks" then
    -- The list is itself a float; the bar has to sit above it.
    zindex = (vim.api.nvim_win_get_config(win).zindex or 50) + 1
  end
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
    zindex = zindex,
    hovered = hovered,
    marks = marks,
    corner = corner(computed),
    content_sig = content_sig,
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
--- @param entry table  the window's bars
--- @param computed table  from `compute`
local function draw_minimap(win, entry, computed)
  local map = computed.minimap
  if not map then
    if entry.minimap then
      entry.minimap:destroy()
      entry.minimap = nil
    end
    return
  end
  entry.minimap = entry.minimap or Bar.new(highlight.MINIMAP)
  -- Hidden rather than destroyed, so it comes back without a rebuild.
  if dodge.covered(win, computed.info, map) then
    entry.minimap:hide()
    return
  end
  entry.minimap:update(win, minimap.bar_opts(win, computed.info, map, marks_updated))
end

--- Whether the minimap of `win` is on screen, so clicks there are its own.
--- @param win integer
--- @return boolean
function M.minimap_shown(win)
  local bar = bars[win] and bars[win].minimap
  return bar ~= nil and bar:is_valid() and not bar.hidden
end

--- Whether the bar with this key is subject to hiding. The minimap stays up unless
--- `minimap.autohide` is set.
local function hides(orientation)
  return orientation ~= "minimap" or config.options.minimap.autohide
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
  local skip_minimap = quiet and hides("minimap") and (not entry.minimap or entry.minimap.hidden)
  if skip_vertical and skip_horizontal and skip_minimap then
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
  if not skip_minimap then
    draw_minimap(win, entry, computed)
  end
end

--- Refresh every ordinary window in the current tabpage.
--- @param quiet boolean|nil  only redraw bars that are already showing
function M.refresh_all(quiet)
  -- Windows that stopped carrying bars are not among the targets below, so
  -- they would otherwise keep them.
  M.prune()
  for _, win in ipairs(util.target_windows()) do
    M.refresh(win, quiet)
  end
end

--- Hide both bars of `win` without destroying them.
--- @param win integer
function M.hide(win)
  local entry = bars[win]
  if entry then
    for orientation, bar in pairs(entry) do
      if hides(orientation) then
        bar:hide()
      end
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
    for _, bar in pairs(entry) do
      bar:destroy()
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

--- Drop bars of windows that no longer exist or no longer carry bars (a
--- buffer turned into a terminal without any event we saw, say).
function M.prune()
  for _, win in ipairs(vim.tbl_keys(bars)) do
    if not util.is_eligible(win) then
      M.clear(win)
    end
  end
end

return M
