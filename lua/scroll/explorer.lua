--- The Snacks explorer's list, as something the vertical bar can measure.
---
--- The list is a float inside the sidebar, and it only ever holds the rows on
--- screen: scrolling rewrites the buffer and moves the picker's `top`, not the
--- window's view. So its offset and length come from the picker. Everything
--- here reaches into Snacks internals and is wrapped in `pcall`: if they
--- change, the explorer just loses its bar.
local config = require("scroll.config")

local M = {}

--- Snacks explorer lists open in this tabpage, by window.
--- @return table<integer, table>
local function lists()
  local out = {}
  local opts = config.options.explorer
  if not (opts.enabled and opts.snacks) then
    return out
  end
  -- Only look when the picker is already loaded; never load Snacks ourselves.
  local core = package.loaded["snacks.picker.core.picker"]
  if not core then
    return out
  end
  local ok, pickers = pcall(core.get, { source = "explorer" })
  if not ok then
    return out
  end
  for _, picker in ipairs(pickers) do
    local win = vim.tbl_get(picker, "list", "win", "win")
    if win then
      out[win] = picker.list
    end
  end
  return out
end

--- The Snacks list shown in `win`, if `win` is one.
--- @param win integer
--- @return table|nil
function M.list_of(win)
  return lists()[win]
end

--- `{ total, offset, page }` for the list in `win`, like `measure.vertical`.
--- @param win integer
--- @param page integer  the window's text height
--- @return table|nil
function M.measure(win, page)
  local list = M.list_of(win)
  if not list or page < 1 then
    return nil
  end
  local ok, total = pcall(list.count, list)
  if not ok or type(list.top) ~= "number" then
    return nil
  end
  return { total = total, offset = list.top - 1, page = page }
end

--- Scroll the list in `win` so item `top` is the first one shown.
--- @param win integer
--- @param top integer  1-based
function M.scroll_to(win, top)
  local list = M.list_of(win)
  -- A reversed list counts from the bottom; the explorer never is one.
  if not list or list.reverse then
    return
  end
  pcall(list.scroll, list, math.max(1, top), true)
end

--- Scroll the list in `win` by `delta` items.
--- @param win integer
--- @param delta integer
function M.scroll_by(win, delta)
  local list = M.list_of(win)
  if list and type(list.top) == "number" then
    M.scroll_to(win, list.top + delta)
  end
end

--- What the lists looked like at the last check, to notice scrolling: Snacks
--- redraws its list without any event we could hook.
local last = ""

--- Whether any explorer list scrolled or changed length since the last call.
--- @return boolean
function M.state_changed()
  local parts = {}
  for win, list in pairs(lists()) do
    local ok, count = pcall(list.count, list)
    parts[#parts + 1] = table.concat({ win, tostring(list.top), ok and count or "" }, ":")
  end
  table.sort(parts)
  local now = table.concat(parts, ",")
  if now == last then
    return false
  end
  last = now
  return true
end

function M.reset()
  last = ""
end

return M
