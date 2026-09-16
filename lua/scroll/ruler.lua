--- Overview ruler: where diagnostics, git changes and search matches sit in
--- the whole buffer, as ticks on the vertical track.
---
--- A mark's place on the track depends only on the document, not on the
--- scroll position, so cells are computed once per change of marks or of the
--- measurement and then reused by every scroll-driven redraw.
local config = require("scroll.config")
local highlight = require("scroll.highlight")
local measure = require("scroll.measure")

local M = {}

local SOURCES = {
  { name = "diagnostics", module = require("scroll.marks.diagnostics") },
  { name = "git", module = require("scroll.marks.git") },
  { name = "search", module = require("scroll.marks.search") },
}

--- Higher priority wins a shared cell. `left` marks take the track's first
--- column, the rest its last; on a 1-column track that is the same cell.
local KINDS = {
  error = { source = "diagnostics", hl = highlight.MARK_ERROR, priority = 90 },
  warn = { source = "diagnostics", hl = highlight.MARK_WARN, priority = 80 },
  search = { source = "search", hl = highlight.MARK_SEARCH, priority = 70 },
  info = { source = "diagnostics", hl = highlight.MARK_INFO, priority = 60 },
  hint = { source = "diagnostics", hl = highlight.MARK_HINT, priority = 50 },
  delete = { source = "git", hl = highlight.MARK_DELETE, priority = 40, left = true },
  change = { source = "git", hl = highlight.MARK_CHANGE, priority = 30, left = true },
  add = { source = "git", hl = highlight.MARK_ADD, priority = 20, left = true },
}

--- @type table<integer, { sig: string, cells: table[] }>
local cache = {}

--- Merge overlapping and adjacent ranges of the same kind, so a block of
--- matches costs one placement instead of one per line.
local function merge(ranges, line_count)
  table.sort(ranges, function(a, b)
    if a.kind ~= b.kind then
      return a.kind < b.kind
    end
    return a.first < b.first
  end)
  local out = {}
  for _, r in ipairs(ranges) do
    local first = math.max(1, math.min(r.first, line_count))
    local last = math.max(first, math.min(r.last, line_count))
    local prev = out[#out]
    if prev and prev.kind == r.kind and first <= prev.last + 1 then
      prev.last = math.max(prev.last, last)
    else
      out[#out + 1] = { first = first, last = last, kind = r.kind }
    end
  end
  return out
end

--- Track rows covered by each range: from the row holding its first line to
--- the row holding its last, and never less than one row.
local function place(win, ranges, track, total)
  local wanted, index = {}, {}
  for _, r in ipairs(ranges) do
    for _, l in ipairs({ r.first, r.last + 1 }) do
      if not index[l] then
        index[l] = true
        wanted[#wanted + 1] = l
      end
    end
  end
  table.sort(wanted)
  local rows = measure.rows_above_lines(win, wanted, total)
  local above = {}
  for i, l in ipairs(wanted) do
    above[l] = rows[i]
  end

  local grid = {}
  local width = config.options.vertical.width
  for _, r in ipairs(ranges) do
    local kind = KINDS[r.kind]
    local col = kind.left and 0 or width - 1
    local top = math.min(track - 1, math.floor(above[r.first] * track / total))
    local bottom = math.ceil(above[r.last + 1] * track / total) - 1
    bottom = math.max(top, math.min(track - 1, bottom))
    for row = top, bottom do
      local key = row * width + col
      local held = grid[key]
      if not held or KINDS[held.kind].priority < kind.priority then
        grid[key] = { row = row, col = col, kind = r.kind }
      end
    end
  end

  local marks = config.options.marks
  local cells = {}
  for _, cell in pairs(grid) do
    local kind = KINDS[cell.kind]
    cells[#cells + 1] = { row = cell.row, col = cell.col, char = marks[kind.source].char, hl = kind.hl }
  end
  table.sort(cells, function(a, b)
    return a.row < b.row or (a.row == b.row and a.col < b.col)
  end)
  return cells
end

--- Mark cells for the vertical track of `win`.
--- @param win integer
--- @param track integer  track length in rows
--- @param total integer  document height, as measured for the thumb
--- @param on_update function|nil  called when an asynchronous source finishes
--- @return table[] cells  `{ row, col, char, hl }`, 0-based within the track
--- @return string sig     changes whenever `cells` does
function M.cells(win, track, total, on_update)
  local marks = config.options.marks
  if not marks.enabled or total < 1 or track < 1 then
    cache[win] = nil
    return {}, ""
  end

  local buf = vim.api.nvim_win_get_buf(win)
  local ranges, parts = {}, {}
  for _, source in ipairs(SOURCES) do
    if marks[source.name].enabled then
      local got, version = source.module.get(buf, on_update)
      parts[#parts + 1] = source.name .. "=" .. tostring(version)
      vim.list_extend(ranges, got)
    end
  end
  local sig = table.concat({
    table.concat(parts, ","),
    measure.signature(win),
    track,
    config.options.vertical.width,
    marks.diagnostics.char,
    marks.git.char,
    marks.search.char,
  }, "|")

  local entry = cache[win]
  if entry and entry.sig == sig then
    return entry.cells, sig
  end

  local cells = {}
  if #ranges > 0 then
    cells = place(win, merge(ranges, vim.api.nvim_buf_line_count(buf)), track, total)
  end
  cache[win] = { sig = sig, cells = cells }
  return cells, sig
end

--- @param win integer
function M.forget_win(win)
  cache[win] = nil
end

--- @param buf integer
function M.forget_buf(buf)
  for _, source in ipairs(SOURCES) do
    source.module.forget(buf)
  end
end

function M.reset()
  cache = {}
  for _, source in ipairs(SOURCES) do
    source.module.reset()
  end
end

return M
