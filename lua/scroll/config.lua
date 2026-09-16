local M = {}

--- @type table
M.defaults = {
  enabled = true,

  vertical = {
    enabled = true,
    width = 1,
    char = "█",
    track_char = "│",
  },
  horizontal = {
    enabled = true,
    height = 1,
    --- A half block: a character cell is about twice as tall as it is wide,
    --- so this matches the thickness of the one-column vertical thumb.
    char = "▄",
    track_char = "─",
  },

  --- Overview ruler: ticks on the vertical track marking where things are in
  --- the whole buffer. Git changes take the track's left column and everything
  --- else the right; on a 1-column track they share it and the most severe
  --- mark wins (error > warning > search > info > hint > git).
  marks = {
    enabled = true,
    diagnostics = {
      enabled = true,
      char = "━",
      --- Passed to `vim.diagnostic.get`, e.g. `{ min = vim.diagnostic.severity.WARN }`.
      severity = nil,
    },
    git = {
      enabled = true,
      char = "▌",
      --- Without gitsigns, changes are found by diffing the buffer against the
      --- index. That costs O(lines), so it is skipped above this size.
      max_lines = 20000,
      --- ms of quiet after an edit before re-diffing, without gitsigns.
      debounce = 200,
    },
    search = {
      enabled = true,
      char = "━",
    },
  },

  --- Plain minimap: the buffer in braille, with a git change gutter and the
  --- viewport highlighted, overlaid left of the vertical bar. Toggle with
  --- `:ScrollMinimapToggle`.
  minimap = {
    enabled = false,
    width = 20, -- columns, including the 1-column git gutter
    columns_per_dot = 2, -- text columns per braille dot column
    min_window_width = 80, -- not drawn in narrower windows
    git = true,
    git_char = "▎",
    winblend = 0,
    --- Hide with the scrollbars when `visibility` hides them. Off by default:
    --- a minimap that keeps vanishing is hard to use.
    autohide = false,
  },

  --- "auto" fade in on activity, hide after `hide_delay` ms of quiet
  --- "always" draw whenever the content overflows
  --- "hover" only while the pointer is near the bar (needs 'mousemoveevent')
  visibility = "auto",
  hide_delay = 1000,

  winblend = 30, -- 0 = opaque, 100 = invisible

  --- Below the default float zindex (50) and well below the insert-completion
  --- popup (100, hard-coded in Neovim), so completion menus, LSP hover and
  --- notification windows all draw over the bar rather than under it. The bar
  --- still covers ordinary window text, which is what we want.
  zindex = 40,

  mouse = true,

  excluded_filetypes = { "help", "qf", "NvimTree", "neo-tree", "TelescopePrompt", "lazy", "mason" },
  excluded_buftypes = { "terminal", "prompt", "nofile", "quickfix" },

  -- Below these sizes a bar costs more screen space than it is worth.
  min_width = 20,
  min_height = 5,

  --- Beyond this many lines, a jump is interpolated instead of measured
  --- exactly, since exact measurement costs O(lines crossed).
  exact_measure_max_lines = 10000,
}

--- @type table
M.options = vim.deepcopy(M.defaults)

--- Sections that may be given as a bare boolean: `minimap = true` is
--- `minimap = { enabled = true }`.
local sections = { "vertical", "horizontal", "marks", "minimap" }
local mark_sources = { "diagnostics", "git", "search" }

--- Validate the parts of a user config where a wrong value would otherwise
--- fail later in a confusing place (inside a redraw, or as a bad window config).
--- @param opts table
local function validate(opts)
  vim.validate("visibility", opts.visibility, function(v)
    return v == "auto" or v == "always" or v == "hover"
  end, 'one of "auto", "always", "hover"')
  vim.validate("hide_delay", opts.hide_delay, "number")
  vim.validate("winblend", opts.winblend, function(v)
    return type(v) == "number" and v >= 0 and v <= 100
  end, "a number between 0 and 100")
  vim.validate("zindex", opts.zindex, "number")
  vim.validate("mouse", opts.mouse, "boolean")
  vim.validate("minimap", opts.minimap, "table")
  vim.validate("minimap.width", opts.minimap.width, function(v)
    return type(v) == "number" and v >= 2
  end, "a number >= 2")
  vim.validate("minimap.columns_per_dot", opts.minimap.columns_per_dot, function(v)
    return type(v) == "number" and v >= 1
  end, "a number >= 1")
  vim.validate("marks", opts.marks, "table")
  for _, source in ipairs(mark_sources) do
    vim.validate("marks." .. source, opts.marks[source], "table")
    vim.validate("marks." .. source .. ".char", opts.marks[source].char, function(v)
      return type(v) == "string" and vim.fn.strdisplaywidth(v) == 1
    end, "a single-cell string")
  end

  if opts.visibility == "hover" and not vim.o.mousemoveevent then
    vim.notify(
      "scroll.nvim: visibility = 'hover' needs `vim.o.mousemoveevent = true` to receive pointer motion",
      vim.log.levels.WARN
    )
  end
end

--- @param tbl table
--- @param key string
local function expand(tbl, key)
  if type(tbl[key]) == "boolean" then
    tbl[key] = { enabled = tbl[key] }
  end
end

--- @param opts table|nil
--- @return table  the merged, validated options
function M.setup(opts)
  opts = vim.deepcopy(opts or {})
  for _, key in ipairs(sections) do
    expand(opts, key)
  end
  if type(opts.marks) == "table" then
    for _, key in ipairs(mark_sources) do
      expand(opts.marks, key)
    end
  end
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts)
  validate(M.options)
  return M.options
end

return M
