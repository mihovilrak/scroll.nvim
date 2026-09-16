--- A plain minimap: the buffer drawn in braille, one cell per block of text,
--- with a git change gutter and the viewport highlighted.
---
--- Each braille cell has 2x4 dots. A dot row is one buffer line and a dot
--- column is `columns_per_dot` display columns, lit when that block holds any
--- non-blank character. So a minimap row covers 4 buffer lines.
---
--- Only the rows actually on screen are rendered -- about 4 * height lines per
--- refresh, regardless of buffer size -- and rendered rows are cached per
--- changedtick, so scrolling mostly reuses them. Deliberately plain: no
--- syntax colours, and folds and wrapping are ignored (a row is always 4
--- buffer lines).
local config = require("scroll.config")
local git = require("scroll.marks.git")
local highlight = require("scroll.highlight")

local M = {}

M.LINES_PER_ROW = 4

--- Braille glyph for each dot pattern, as UTF-8.
--- @type string[]  indexed by pattern + 1
local GLYPH = {}
for bits = 0, 255 do
  local cp = 0x2800 + bits
  GLYPH[bits + 1] = string.char(0xE0 + math.floor(cp / 0x1000), 0x80 + math.floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
end

--- Dot bit for dot column `x` (0-1) and dot row `y` (0-3), per the Unicode
--- braille layout (dots 1-2-3-7 down the left, 4-5-6-8 down the right).
local DOT = {
  [0] = { [0] = 0x01, 0x02, 0x04, 0x40 },
  [1] = { [0] = 0x08, 0x10, 0x20, 0x80 },
}

--- Set the dots of dot row `y` for `line` into `cells` (0-based cell index ->
--- bit pattern). Tabs are expanded; any other character counts as one
--- column, so double-width text is slightly compressed.
--- @param line string
--- @param y integer
--- @param cells table<integer, integer>
--- @param ncells integer
--- @param per_dot integer  display columns per dot column
--- @param tabstop integer
local function plot(line, y, cells, ncells, per_dot, tabstop)
  local limit = ncells * 2 * per_dot
  local col = 0
  for i = 1, #line do
    local b = line:byte(i)
    if b == 9 then
      col = col + tabstop - col % tabstop
    elseif b < 0x80 or b >= 0xC0 then -- skip UTF-8 continuation bytes
      if b ~= 32 then
        local x = math.floor(col / per_dot)
        local cell = math.floor(x / 2)
        cells[cell] = bit.bor(cells[cell] or 0, DOT[x % 2][y])
      end
      col = col + 1
    end
    if col >= limit then
      break
    end
  end
end

--- Render one minimap row from up to 4 buffer lines. Pure; exported for tests.
--- @param lines string[]
--- @param ncells integer  braille cells in the row
--- @param per_dot integer
--- @param tabstop integer
--- @return string
function M.encode(lines, ncells, per_dot, tabstop)
  local cells = {}
  for y = 0, M.LINES_PER_ROW - 1 do
    local line = lines[y + 1]
    if line and line ~= "" then
      plot(line, y, cells, ncells, per_dot, tabstop)
    end
  end
  local out = {}
  for c = 0, ncells - 1 do
    out[c + 1] = GLYPH[(cells[c] or 0) + 1]
  end
  return table.concat(out)
end

--- Which minimap rows are on screen, and where the viewport is among them.
--- Pure; exported for tests.
---
--- When the whole map fits, it is drawn from the top. Otherwise it scrolls in
--- proportion to the window, so its first row shows at the top of the buffer
--- and its last at the end, and it is nudged so the viewport stays visible.
--- @param o { height: integer, line_count: integer, topline: integer, botline: integer }
--- @return { rows: integer, offset: integer, view_top: integer, view_bottom: integer }
---   `offset` is the first map row shown; `view_*` are 0-based rows within the float.
function M.layout(o)
  local per_row = M.LINES_PER_ROW
  local rows = math.ceil(o.line_count / per_row)
  local view_top = math.floor((o.topline - 1) / per_row)
  local view_bottom = math.floor((math.min(o.botline, o.line_count) - 1) / per_row)

  local offset = 0
  if rows > o.height then
    local max_offset = rows - o.height
    local scrollable = o.line_count - (o.botline - o.topline + 1)
    if scrollable > 0 then
      local frac = math.min(1, math.max(0, (o.topline - 1) / scrollable))
      offset = math.floor(frac * max_offset + 0.5)
    end
    if view_bottom >= offset + o.height then
      offset = view_bottom - o.height + 1
    end
    if view_top < offset then
      offset = view_top
    end
    offset = math.max(0, math.min(offset, max_offset))
  end

  return {
    rows = rows,
    offset = offset,
    view_top = view_top - offset,
    view_bottom = math.min(view_bottom - offset, o.height - 1),
  }
end

--- Where the minimap goes in `win`, or nil when it should not be drawn.
--- @param info table  getwininfo() entry
--- @return { col: integer, width: integer, offset: integer, view_top: integer, view_bottom: integer }|nil
function M.compute(win, info)
  local opts = config.options
  local mm = opts.minimap
  if not mm.enabled or info.width < mm.min_window_width or info.height < 1 then
    return nil
  end
  local right = opts.vertical.enabled and opts.vertical.width or 0
  local buf = vim.api.nvim_win_get_buf(win)
  local l = M.layout({
    height = info.height,
    line_count = vim.api.nvim_buf_line_count(buf),
    topline = info.topline,
    botline = info.botline,
  })
  return {
    col = info.width - right - mm.width,
    width = mm.width,
    offset = l.offset,
    rows = l.rows,
    view_top = l.view_top,
    view_bottom = l.view_bottom,
  }
end

--- The buffer line a minimap row starts at.
--- @param map table  from `compute`
--- @param row integer  0-based row within the float
--- @return integer
function M.line_at(map, row)
  return (map.offset + row) * M.LINES_PER_ROW + 1
end

--- @type table<integer, { key: string, rows: table<integer, string> }>
local rendered = {}

--- Text of map rows `offset .. offset + height - 1` for `buf`.
local function rows_for(buf, offset, height, ncells)
  local mm = config.options.minimap
  local tabstop = vim.bo[buf].tabstop
  local key = table.concat({ vim.api.nvim_buf_get_changedtick(buf), ncells, mm.columns_per_dot, tabstop }, ":")
  local cache = rendered[buf]
  if not cache or cache.key ~= key then
    cache = { key = key, rows = {} }
    rendered[buf] = cache
  end

  local per_row = M.LINES_PER_ROW
  local line_count = vim.api.nvim_buf_line_count(buf)
  local out = {}
  local missing_from = nil
  for i = 0, height - 1 do
    local r = offset + i
    if r * per_row >= line_count then
      break
    end
    if not cache.rows[r] then
      missing_from = missing_from or r
    end
  end

  if missing_from then
    -- One fetch covers every uncached row from the first gap down.
    local last_row = offset + height - 1
    local lines = vim.api.nvim_buf_get_lines(buf, missing_from * per_row, (last_row + 1) * per_row, false)
    for r = missing_from, last_row do
      if not cache.rows[r] then
        local base = (r - missing_from) * per_row
        if base >= #lines then
          break
        end
        cache.rows[r] = M.encode(
          { lines[base + 1], lines[base + 2], lines[base + 3], lines[base + 4] },
          ncells,
          mm.columns_per_dot,
          tabstop
        )
      end
    end
  end

  local blank = string.rep(" ", ncells)
  for i = 0, height - 1 do
    out[i + 1] = cache.rows[offset + i] or blank
  end
  return out
end

--- Git change kind per map row, most significant first.
local GIT_RANK = { delete = 3, change = 2, add = 1 }
local GIT_HL = { delete = highlight.MARK_DELETE, change = highlight.MARK_CHANGE, add = highlight.MARK_ADD }

local function git_gutter(buf, offset, height, on_update)
  local mm = config.options.minimap
  if not mm.git or not config.options.marks.git.enabled then
    return {}, ""
  end
  local ranges, version = git.get(buf, on_update)
  local per_row = M.LINES_PER_ROW
  local rows = {}
  for _, r in ipairs(ranges) do
    local top = math.max(offset, math.floor((r.first - 1) / per_row))
    local bottom = math.min(offset + height - 1, math.floor((r.last - 1) / per_row))
    for row = top, bottom do
      local held = rows[row - offset]
      if not held or GIT_RANK[held] < GIT_RANK[r.kind] then
        rows[row - offset] = r.kind
      end
    end
  end
  return rows, tostring(version)
end

--- Fill `buf` (the minimap float's buffer) for the current view.
--- @param float_buf integer
--- @param opts table  as passed to `Bar:update`, plus `source`, `map`
local function paint(float_buf, ns, opts)
  local map, height = opts.map, opts.height
  local ncells = opts.width - 1 -- first column is the git gutter
  local rows = rows_for(opts.source, map.offset, height, ncells)
  local lines = {}
  for i, text in ipairs(rows) do
    lines[i] = " " .. text
  end
  vim.api.nvim_buf_set_lines(float_buf, 0, -1, false, lines)
  vim.api.nvim_buf_clear_namespace(float_buf, ns, 0, -1)

  for row = math.max(0, map.view_top), map.view_bottom do
    vim.api.nvim_buf_set_extmark(float_buf, ns, row, 0, {
      line_hl_group = highlight.MINIMAP_VIEWPORT,
      priority = 100,
    })
  end
  for row, kind in pairs(opts.gutter) do
    vim.api.nvim_buf_set_extmark(float_buf, ns, row, 0, {
      virt_text = { { config.options.minimap.git_char, GIT_HL[kind] } },
      virt_text_pos = "overlay",
      hl_mode = "combine",
      priority = 300,
    })
  end
end

--- Options for `Bar:update` that draw the minimap of `win`.
--- @param win integer
--- @param info table
--- @param map table  from `compute`
--- @param on_update function|nil
--- @return table
function M.bar_opts(win, info, map, on_update)
  local mm = config.options.minimap
  local buf = vim.api.nvim_win_get_buf(win)
  local gutter, git_sig = git_gutter(buf, map.offset, info.height, on_update)
  return {
    row = info.winbar,
    col = map.col,
    width = map.width,
    height = info.height,
    winblend = mm.winblend,
    zindex = config.options.zindex,
    source = buf,
    map = map,
    gutter = gutter,
    paint = paint,
    content_sig = table.concat({
      buf,
      vim.api.nvim_buf_get_changedtick(buf),
      map.offset,
      map.view_top,
      map.view_bottom,
      git_sig,
      mm.columns_per_dot,
      vim.bo[buf].tabstop,
    }, ":"),
  }
end

--- @param buf integer
function M.forget(buf)
  rendered[buf] = nil
end

function M.reset()
  rendered = {}
end

return M
