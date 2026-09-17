--- A plain minimap: the buffer drawn in braille, one cell per block of text,
--- with a git change gutter, the viewport highlighted and the cursor's row
--- underlined. Only ordinary file buffers get one.
---
--- Each braille cell has 2x4 dots. A dot row is one buffer line and a dot
--- column is `columns_per_dot` display columns, lit when that block holds any
--- non-blank character. So a minimap row covers 4 buffer lines.
---
--- Only the rows actually on screen are rendered -- about 4 * height lines per
--- refresh, regardless of buffer size -- and rendered rows are cached per
--- changedtick, so scrolling mostly reuses them. With `colors`, each cell
--- takes the highlight group covering most of its text, from treesitter or
--- else `:syntax`. Folds and wrapping are ignored (a row is always 4 buffer
--- lines).
local config = require("scroll.config")
local git = require("scroll.marks.git")
local highlight = require("scroll.highlight")
local util = require("scroll.util")

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
--- column, so double-width text is slightly compressed. With `groups` (byte
--- index -> highlight group), also tally each cell's groups into `counts`.
--- @param line string
--- @param y integer
--- @param cells table<integer, integer>
--- @param ncells integer
--- @param per_dot integer  display columns per dot column
--- @param tabstop integer
--- @param groups table<integer, string>|nil
--- @param counts table<integer, table<string, integer>>
local function plot(line, y, cells, ncells, per_dot, tabstop, groups, counts)
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
        local group = groups and groups[i]
        if group then
          local tally = counts[cell]
          if not tally then
            tally = {}
            counts[cell] = tally
          end
          tally[group] = (tally[group] or 0) + 1
        end
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
--- @param groups (table<integer, string>|false)[]|nil  per line, byte index -> highlight group
--- @return string text
--- @return { [1]: integer, [2]: integer, [3]: string }[] spans  0-based cell ranges (end exclusive) and their group
function M.encode(lines, ncells, per_dot, tabstop, groups)
  local cells, counts = {}, {}
  for y = 0, M.LINES_PER_ROW - 1 do
    local line = lines[y + 1]
    if line and line ~= "" then
      plot(line, y, cells, ncells, per_dot, tabstop, groups and groups[y + 1] or nil, counts)
    end
  end
  local out, spans = {}, {}
  local last = nil
  for c = 0, ncells - 1 do
    out[c + 1] = GLYPH[(cells[c] or 0) + 1]
    local best, most = nil, 0
    for group, n in pairs(counts[c] or {}) do
      -- Ties go to the alphabetically first group, so the result is stable.
      if n > most or (n == most and group < best) then
        best, most = group, n
      end
    end
    if best then
      if last and last[2] == c and last[3] == best then
        last[2] = c + 1
      else
        last = { c, c + 1, best }
        spans[#spans + 1] = last
      end
    end
  end
  return table.concat(out), spans
end

--- Where the buffer's colours come from: "treesitter", "syntax:<name>", or
--- nil when colours are off or the buffer has none.
--- @param buf integer
--- @return string|nil
local function color_source(buf)
  if not config.options.minimap.colors then
    return nil
  end
  if vim.treesitter.highlighter.active[buf] then
    return "treesitter"
  end
  local syntax = vim.b[buf].current_syntax
  if syntax and vim.g.syntax_on then
    return "syntax:" .. syntax
  end
  return nil
end

--- Treesitter captures to leave out: they carry no colour of their own.
local SKIP_CAPTURE = { spell = true, nospell = true, conceal = true }

--- Buffers with a background parse under way, and how many have finished.
--- @type table<integer, true>
local parsing = {}
--- @type table<integer, integer>
local parsed = {}

--- Whether `buf`'s trees are up to date for rows `first .. last - 1`. If not,
--- start a background parse that calls `on_update` when done: after an edit
--- a big file can take hundreds of milliseconds to reparse, which must not
--- block a refresh.
local function ts_ready(buf, parser, first, last, on_update)
  local range = { first, last }
  if parser:is_valid(false, range) then
    return true
  end
  if not parsing[buf] then
    parsing[buf] = true
    parser:parse(range, function(_, trees)
      parsing[buf] = nil
      if trees then
        parsed[buf] = (parsed[buf] or 0) + 1
        if on_update then
          on_update()
        end
      end
    end)
  end
  -- The parse finishes synchronously when `vim.g._ts_force_sync_parsing` is set.
  return parser:is_valid(false, range)
end

--- Fill `out` (per line of `lines`, byte index -> group) from treesitter.
--- @param buf integer
--- @param first integer  0-based buffer row of `lines[1]`
--- @param lines string[]
--- @param out table<integer, string>[]
--- @return boolean final  false when drawn from outdated trees
local function treesitter_groups(buf, first, lines, out, on_update)
  local last = first + #lines -- exclusive
  local parser = vim.treesitter.highlighter.active[buf].tree
  local final = ts_ready(buf, parser, first, last, on_update)
  parser:for_each_tree(function(tstree, ltree)
    local lang = ltree:lang()
    local query = vim.treesitter.query.get(lang, "highlights")
    local root = tstree and tstree:root()
    if not query or not root then
      return
    end
    local root_start, _, root_end = root:range()
    if root_end < first or root_start >= last then
      return
    end
    -- Captures come in pattern order, later ones overriding, as in the
    -- highlighter itself; injected trees come after their parent.
    for id, node in query:iter_captures(root, buf, first, last) do
      local name = query.captures[id]
      if name:byte(1) ~= 95 and not SKIP_CAPTURE[name] then -- 95 = "_"
        local group = "@" .. name .. "." .. lang
        local sr, sc, er, ec = node:range()
        for row = math.max(sr, first), math.min(er, last - 1) do
          local i = row - first + 1
          local to = row == er and ec or #lines[i]
          local groups = out[i]
          for b = (row == sr and sc or 0) + 1, to do
            groups[b] = group
          end
        end
      end
    end
  end)
  return final
end

--- Fill `out` from `:syntax`, one lookup per word, and only as far into each
--- line as the map can show.
--- @param buf integer
--- @param first integer
--- @param lines string[]
--- @param out table<integer, string>[]
--- @param limit integer  display columns shown
--- @param tabstop integer
local function syntax_groups(buf, first, lines, out, limit, tabstop)
  local names = {}
  vim.api.nvim_buf_call(buf, function()
    for i, line in ipairs(lines) do
      local groups = out[i]
      local col, in_word, group = 0, false, nil
      for b = 1, #line do
        local byte = line:byte(b)
        if byte == 32 or byte == 9 then
          in_word = false
          col = byte == 9 and col + tabstop - col % tabstop or col + 1
        else
          if not in_word then
            in_word = true
            local id = vim.fn.synID(first + i, b, 1)
            if names[id] == nil then
              names[id] = id ~= 0 and vim.fn.synIDattr(id, "name") or false
            end
            group = names[id] or nil
          end
          groups[b] = group
          if byte < 0x80 or byte >= 0xC0 then
            col = col + 1
          end
        end
        if col >= limit then
          break
        end
      end
    end
  end)
end

--- Highlight groups for `lines` (buffer rows from 0-based `first`), per line
--- as byte index -> group, or nil when the map is not coloured.
--- @return table<integer, string>[]|nil groups
--- @return boolean final  false when a parse is pending and the rows should not be cached
local function groups_for(buf, source, first, lines, limit, tabstop, on_update)
  if not source then
    return nil, true
  end
  local out = {}
  for i = 1, #lines do
    out[i] = {}
  end
  local ok, final
  if source == "treesitter" then
    ok, final = pcall(treesitter_groups, buf, first, lines, out, on_update)
  else
    ok, final = pcall(syntax_groups, buf, first, lines, out, limit, tabstop)
    final = true
  end
  if not ok then
    -- A broken parser or query should cost the colours, not the map.
    vim.notify_once("scroll.nvim: minimap colours unavailable: " .. tostring(final), vim.log.levels.WARN)
    return nil, true
  end
  return out, final
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
  if not util.minimap_eligible(win) then
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

--- @type table<integer, { key: string, rows: table<integer, string>, spans: table<integer, table> }>
local rendered = {}

--- Text and colour spans of map rows `offset .. offset + height - 1` for `buf`.
local function rows_for(buf, offset, height, ncells, on_update)
  local mm = config.options.minimap
  local tabstop = vim.bo[buf].tabstop
  local source = color_source(buf)
  local key =
    table.concat({ vim.api.nvim_buf_get_changedtick(buf), ncells, mm.columns_per_dot, tabstop, source or "" }, ":")
  local cache = rendered[buf]
  if not cache or cache.key ~= key then
    cache = { key = key, rows = {}, spans = {} }
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

  -- Rows drawn while a parse is pending are shown once but not kept.
  local fresh = cache
  if missing_from then
    -- One fetch covers every uncached row from the first gap down.
    local last_row = offset + height - 1
    local first = missing_from * per_row
    local lines = vim.api.nvim_buf_get_lines(buf, first, (last_row + 1) * per_row, false)
    local groups, final = groups_for(buf, source, first, lines, ncells * 2 * mm.columns_per_dot, tabstop, on_update)
    if not final then
      fresh = { rows = {}, spans = {} }
    end
    for r = missing_from, last_row do
      if not cache.rows[r] then
        local base = (r - missing_from) * per_row
        if base >= #lines then
          break
        end
        fresh.rows[r], fresh.spans[r] = M.encode(
          { lines[base + 1], lines[base + 2], lines[base + 3], lines[base + 4] },
          ncells,
          mm.columns_per_dot,
          tabstop,
          groups and { groups[base + 1], groups[base + 2], groups[base + 3], groups[base + 4] }
        )
      end
    end
  end

  local blank = string.rep(" ", ncells)
  local spans = {}
  for i = 0, height - 1 do
    local r = offset + i
    out[i + 1] = cache.rows[r] or fresh.rows[r] or blank
    spans[i + 1] = cache.spans[r] or fresh.spans[r]
  end
  return out, spans
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
  local rows, spans = rows_for(opts.source, map.offset, height, ncells, opts.on_update)
  local lines = {}
  for i, text in ipairs(rows) do
    lines[i] = " " .. text
  end
  vim.api.nvim_buf_set_lines(float_buf, 0, -1, false, lines)
  vim.api.nvim_buf_clear_namespace(float_buf, ns, 0, -1)

  -- Each braille glyph is 3 bytes, after the 1-byte gutter.
  for i, row_spans in pairs(spans) do
    for _, span in ipairs(row_spans) do
      vim.api.nvim_buf_set_extmark(float_buf, ns, i - 1, 1 + 3 * span[1], {
        end_col = 1 + 3 * span[2],
        hl_group = span[3],
        -- Above the viewport, so a `Visual` with its own foreground does not
        -- wash the colours out of the visible region.
        priority = 200,
      })
    end
  end
  for row = math.max(0, map.view_top), map.view_bottom do
    vim.api.nvim_buf_set_extmark(float_buf, ns, row, 0, {
      line_hl_group = highlight.MINIMAP_VIEWPORT,
      priority = 100,
    })
  end
  if opts.cursor_row and opts.cursor_row >= 0 and opts.cursor_row < #lines then
    vim.api.nvim_buf_set_extmark(float_buf, ns, opts.cursor_row, 0, {
      line_hl_group = highlight.MINIMAP_CURSOR,
      priority = 150,
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
  local cursor_row = nil
  if mm.cursor then
    local lnum = vim.api.nvim_win_get_cursor(win)[1]
    cursor_row = math.floor((lnum - 1) / M.LINES_PER_ROW) - map.offset
  end
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
    cursor_row = cursor_row,
    on_update = on_update,
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
      color_source(buf) or "",
      parsed[buf] or 0,
      tostring(cursor_row),
    }, ":"),
  }
end

--- @param buf integer
function M.forget(buf)
  rendered[buf] = nil
  parsing[buf] = nil
  parsed[buf] = nil
end

function M.reset()
  rendered = {}
  parsing = {}
  parsed = {}
end

return M
