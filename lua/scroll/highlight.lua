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

local links = {
  [M.TRACK] = "PmenuSbar",
  [M.THUMB] = "PmenuThumb",
  [M.THUMB_HOVER] = "PmenuThumb",
}

function M.setup()
  for group, target in pairs(links) do
    vim.api.nvim_set_hl(0, group, { link = target, default = true })
  end

  -- The hover thumb should read as "brighter" than the resting one. Only
  -- synthesize it when the user has not defined it and we can actually find a
  -- colour to work from; otherwise the link above stands.
  local ok, thumb = pcall(vim.api.nvim_get_hl, 0, { name = M.THUMB, link = false })
  if ok and (thumb.bg or thumb.fg) then
    vim.api.nvim_set_hl(0, M.THUMB_HOVER, {
      bg = thumb.bg,
      fg = thumb.fg,
      bold = true,
      default = true,
    })
  end
end

return M
