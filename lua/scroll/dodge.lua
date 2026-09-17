--- Keeping the minimap from hiding text.
---
--- The minimap is a float over the right end of the text area, and Nvim has
--- no way to shrink a window's text area for it. So instead:
---   margin  with 'nowrap', scroll sideways as if the window ended where the
---           map starts, so the cursor never goes under it
---   covered the map is hidden while the cursor or a Visual selection is
---           under it (with 'wrap', or with the margin turned off)
local config = require("scroll.config")
local minimap = require("scroll.minimap")
local util = require("scroll.util")

local M = {}

--- Scroll `win` sideways so the cursor stays left of its minimap. Run from
--- `CursorMoved`, before the screen is redrawn, so the view never flickers
--- under the map first.
--- @param win integer
function M.keep_clear(win)
  local mm = config.options.minimap
  if not (mm.enabled and mm.dodge.margin) or vim.wo[win].wrap then
    return
  end
  local info = vim.fn.getwininfo(win)[1]
  local map = info and minimap.compute(win, info)
  if not map then
    return
  end
  local usable = map.col - info.textoff -- text columns left of the map
  if usable < 1 then
    return
  end
  vim.api.nvim_win_call(win, function()
    local _, right = util.margins(win, "sidescrolloff", usable, math.floor(usable / 2))
    -- The last display column of the character under the cursor, 0-based.
    local last = vim.fn.virtcol(".", true)[2] - 1
    local leftcol = vim.fn.winsaveview().leftcol
    local limit = usable - 1 - right
    if last - leftcol > limit then
      vim.fn.winrestview({ leftcol = last - limit })
    end
  end)
end

--- The rightmost display column (1-based) the Visual selection reaches on
--- line `l`, or nil when `l` is not selected.
--- @param l integer
--- @param mode string  "v", "V" or CTRL-V
--- @param s integer[]  `{ lnum, vcol }` of the selection's start, 1-based
--- @param e integer[]  the same for its end
--- @param wide boolean  whether the block extends to the end of every line
local function selected_right(l, mode, s, e, wide)
  if l < s[1] or l > e[1] then
    return nil
  end
  local eol = vim.fn.virtcol({ l, "$" }) - 1
  if mode == "V" or (mode == "v" and l < e[1]) or wide then
    return eol
  end
  if mode == "v" then
    return math.min(e[2], eol)
  end
  return math.min(math.max(s[2], e[2]), eol) -- block
end

--- Whether the Visual selection in `win` reaches display column `from`
--- (0-based, counting from the first text column) on any visible line.
local function selection_reaches(win, info, from)
  return vim.api.nvim_win_call(win, function()
    local mode = vim.fn.mode()
    if mode ~= "v" and mode ~= "V" and mode ~= "\22" then
      return false
    end
    local a = { vim.fn.line("v"), vim.fn.virtcol("v") }
    local b = { vim.fn.line("."), vim.fn.virtcol(".") }
    if a[1] > b[1] or (a[1] == b[1] and a[2] > b[2]) then
      a, b = b, a
    end
    local wide = mode == "\22" and vim.fn.winsaveview().curswant == vim.v.maxcol
    local leftcol = vim.wo[win].wrap and 0 or info.leftcol
    for l = math.max(a[1], info.topline), math.min(b[1], info.botline) do
      local right = selected_right(l, mode, a, b, wide)
      if right and right - 1 - leftcol >= from then
        return true
      end
    end
    return false
  end)
end

--- Whether the minimap `map` of `win` should stand aside right now.
--- @param win integer
--- @param info table  getwininfo() entry
--- @param map table  from `minimap.compute`
--- @return boolean
function M.covered(win, info, map)
  if not config.options.minimap.dodge.hide or win ~= vim.api.nvim_get_current_win() then
    return false
  end
  local cursor = vim.api.nvim_win_get_cursor(win)
  local pos = vim.fn.screenpos(win, cursor[1], cursor[2] + 1)
  if pos.col > 0 then
    local col = pos.col - info.wincol -- 0-based within the window
    if col >= map.col and col < map.col + map.width then
      return true
    end
  end
  return selection_reaches(win, info, map.col - info.textoff)
end

return M
