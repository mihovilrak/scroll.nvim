--- Highlight groups, derived from whatever colorscheme is active.
---
--- Defaults are linked rather than hard-coded so a colorscheme that styles
--- `PmenuSbar`/`PmenuThumb` gets sensible bars for free. `default = true` on
--- every definition means a user's own `:highlight` survives our setup and any
--- later `ColorScheme` re-derivation.
local M = {}

M.TRACK = "ScrollTrack"
M.THUMB = "ScrollThumb"
M.THUMB_HOVER = "ScrollThumbHover"

--- Internal: what the thumb's cells are actually drawn with. See `setup`.
M.THUMB_CELL = "ScrollThumbCell"
M.THUMB_CELL_HOVER = "ScrollThumbCellHover"

M.MINIMAP = "ScrollMinimap"
M.MINIMAP_VIEWPORT = "ScrollMinimapViewport"

M.MARK_ERROR = "ScrollMarkError"
M.MARK_WARN = "ScrollMarkWarn"
M.MARK_INFO = "ScrollMarkInfo"
M.MARK_HINT = "ScrollMarkHint"
M.MARK_SEARCH = "ScrollMarkSearch"
M.MARK_ADD = "ScrollMarkAdd"
M.MARK_CHANGE = "ScrollMarkChange"
M.MARK_DELETE = "ScrollMarkDelete"

local links = {
  [M.TRACK] = "PmenuSbar",
  [M.THUMB] = "PmenuThumb",
  [M.THUMB_HOVER] = "PmenuThumb",
  [M.MINIMAP] = "NormalFloat",
  [M.MINIMAP_VIEWPORT] = "Visual",
  [M.MARK_ERROR] = "DiagnosticError",
  [M.MARK_WARN] = "DiagnosticWarn",
  [M.MARK_INFO] = "DiagnosticInfo",
  [M.MARK_HINT] = "DiagnosticHint",
}

--- Git marks follow gitsigns' colours when a colorscheme styles them, and
--- Nvim's own diff groups otherwise.
local git_links = {
  [M.MARK_ADD] = { "GitSignsAdd", "Added" },
  [M.MARK_CHANGE] = { "GitSignsChange", "Changed" },
  [M.MARK_DELETE] = { "GitSignsDelete", "Removed" },
}

local function get(name)
  local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = name, link = false })
  return ok and hl or {}
end

function M.setup()
  for group, target in pairs(links) do
    vim.api.nvim_set_hl(0, group, { link = target, default = true })
  end

  -- The hover thumb should read as "brighter" than the resting one. Only
  -- synthesize it when the user has not defined it and we can actually find a
  -- colour to work from; otherwise the link above stands.
  local thumb = get(M.THUMB)
  if thumb.bg or thumb.fg then
    vim.api.nvim_set_hl(0, M.THUMB_HOVER, {
      bg = thumb.bg,
      fg = thumb.fg,
      bold = true,
      default = true,
    })
  end

  -- The thumb glyph is drawn in the thumb's foreground (the text colour when
  -- the colorscheme only styles `PmenuThumb`'s background, as most do). The
  -- rest of the cell takes the track's background, so a partial block such as
  -- "▄" really is half a cell thick instead of sitting on a thumb-coloured
  -- square. These are derived, not user-facing, so they are always rewritten.
  local normal = get("Normal")
  local track_bg = get(M.TRACK).bg
  for cell, source in pairs({ [M.THUMB_CELL] = M.THUMB, [M.THUMB_CELL_HOVER] = M.THUMB_HOVER }) do
    local hl = get(source)
    vim.api.nvim_set_hl(0, cell, { fg = hl.fg or normal.fg, bg = track_bg, bold = hl.bold })
  end

  for group, candidates in pairs(git_links) do
    local target = candidates[2]
    if next(get(candidates[1])) then
      target = candidates[1]
    end
    vim.api.nvim_set_hl(0, group, { link = target, default = true })
  end

  -- Marks are glyphs drawn in the foreground, but `Search` is usually styled
  -- as a background. Lift that colour into the foreground so the tick is
  -- visible without painting a block over the track.
  local search = get("Search")
  local color = search.bg or search.fg
  if color then
    vim.api.nvim_set_hl(0, M.MARK_SEARCH, { fg = color, default = true })
  else
    vim.api.nvim_set_hl(0, M.MARK_SEARCH, { link = "Search", default = true })
  end
end

return M
