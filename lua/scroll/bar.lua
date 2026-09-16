--- One scrollbar: a floating window, its scratch buffer, and the thumb drawn
--- inside it.
---
--- Floats are created once and then only reconfigured. Hiding uses the `hide`
--- window-config flag rather than closing, which keeps the float handle valid
--- and makes show/hide a single API call with no buffer churn and no flicker.
local highlight = require("scroll.highlight")

local ns = vim.api.nvim_create_namespace("scroll.nvim")

local Bar = {}
Bar.__index = Bar

--- @return table
function Bar.new()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "scrollbar"
  return setmetatable({ buf = buf, win = nil, drawn = nil, hidden = true }, Bar)
end

function Bar:is_valid()
  return self.win ~= nil and vim.api.nvim_win_is_valid(self.win)
end

--- Build the buffer contents and the thumb's byte range.
---
--- The lines are constructed here rather than highlighted in place so the byte
--- offsets of the thumb are known exactly. Track and thumb glyphs are
--- usually multi-byte, so a column index is not a byte index.
local function paint(buf, opts)
  local lines, mark = {}, nil

  if opts.orientation == "vertical" then
    local track_line = string.rep(opts.track_char, opts.width)
    local thumb_line = string.rep(opts.char, opts.width)
    for i = 1, opts.length do
      local in_thumb = i > opts.pos and i <= opts.pos + opts.size
      lines[i] = in_thumb and thumb_line or track_line
    end
    mark = {
      start_row = opts.pos,
      start_col = 0,
      end_row = opts.pos + opts.size - 1,
      end_col = #thumb_line,
    }
  else
    local before = string.rep(opts.track_char, opts.pos)
    local thumb = string.rep(opts.char, opts.size)
    local after = string.rep(opts.track_char, opts.length - opts.pos - opts.size)
    lines[1] = before .. thumb .. after
    mark = {
      start_row = 0,
      start_col = #before,
      end_row = 0,
      end_col = #before + #thumb,
    }
  end

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  vim.api.nvim_buf_set_extmark(buf, ns, mark.start_row, mark.start_col, {
    end_row = mark.end_row,
    end_col = mark.end_col,
    hl_group = opts.hovered and highlight.THUMB_HOVER or highlight.THUMB,
    hl_eol = true,
    priority = 200,
  })

  -- Ruler marks replace the glyph in their cell but keep its background
  -- (`combine`), so a mark reads the same on the track and on the thumb.
  for _, m in ipairs(opts.marks or {}) do
    local glyph = (m.row >= opts.pos and m.row < opts.pos + opts.size) and opts.char or opts.track_char
    vim.api.nvim_buf_set_extmark(buf, ns, m.row, m.col * #glyph, {
      virt_text = { { m.char, m.hl } },
      virt_text_pos = "overlay",
      hl_mode = "combine",
      priority = 300,
    })
  end
end

--- Create or reposition the float and redraw the thumb.
---
--- @param parent integer window the bar is attached to
--- @param opts table
---   orientation "vertical"|"horizontal"
---   row,col     position within `parent`
---   width       float width in columns
---   height      float height in rows
---   length      cells along the bar's axis (height for vertical, width for horizontal)
---   pos,size    thumb placement along that axis
---   char, track_char, winblend, zindex, hovered
---   marks       ruler cells `{ row, col, char, hl }` (vertical only)
---   marks_sig   changes whenever `marks` does
function Bar:update(parent, opts)
  -- Skip the redraw entirely when nothing observable changed. Scroll events
  -- fire far more often than the thumb actually moves.
  local sig = table.concat({
    parent, opts.row, opts.col, opts.width, opts.height,
    opts.pos, opts.size, tostring(opts.hovered), opts.char, opts.track_char,
    opts.marks_sig or "",
  }, ":")
  if self.drawn == sig and self:is_valid() and not self.hidden then
    return
  end

  local win_cfg = {
    relative = "win",
    win = parent,
    row = opts.row,
    col = opts.col,
    width = opts.width,
    height = opts.height,
    focusable = false,
    -- Takes mouse events (so the thumb can be dragged) without joining
    -- window cycling. These two flags are independent.
    mouse = true,
    zindex = opts.zindex,
    style = "minimal",
    hide = false,
  }

  if self:is_valid() then
    vim.api.nvim_win_set_config(self.win, win_cfg)
  else
    win_cfg.noautocmd = true
    self.win = vim.api.nvim_open_win(self.buf, false, win_cfg)
    vim.wo[self.win].winhighlight = ("Normal:%s,NormalFloat:%s,EndOfBuffer:%s"):format(
      highlight.TRACK,
      highlight.TRACK,
      highlight.TRACK
    )
  end

  vim.wo[self.win].winblend = opts.winblend
  paint(self.buf, opts)

  self.drawn = sig
  self.hidden = false
end

function Bar:hide()
  if self.hidden or not self:is_valid() then
    return
  end
  vim.api.nvim_win_set_config(self.win, { hide = true })
  self.hidden = true
end

function Bar:show()
  if not self.hidden or not self:is_valid() then
    return
  end
  vim.api.nvim_win_set_config(self.win, { hide = false })
  self.hidden = false
end

function Bar:close()
  if self:is_valid() then
    vim.api.nvim_win_close(self.win, true)
  end
  self.win = nil
  self.drawn = nil
  self.hidden = true
end

function Bar:destroy()
  self:close()
  if vim.api.nvim_buf_is_valid(self.buf) then
    vim.api.nvim_buf_delete(self.buf, { force = true })
  end
end

return Bar
