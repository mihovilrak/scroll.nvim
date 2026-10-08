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
    --- Start and end of the code block around the cursor (function, `if`,
    --- loop, ...), found with treesitter. Drawn under every other mark.
    scope = {
      enabled = true,
      char = "─",
      --- A treesitter node is a scope when one of the `_`-separated words of
      --- its type is listed here (`if_statement`, `function_definition`, ...).
      --- The innermost multi-line one around the cursor is marked.
      node_types = {
        "function",
        "method",
        "lambda",
        "closure",
        "if",
        "elif",
        "else",
        "for",
        "while",
        "loop",
        "repeat",
        "do",
        "class",
        "struct",
        "impl",
        "interface",
        "switch",
        "case",
        "match",
        "try",
        "catch",
        "with",
      },
    },
  },

  --- Plain minimap: the buffer in braille, with a git change gutter and the
  --- viewport highlighted, overlaid left of the vertical bar. Toggle with
  --- `:ScrollMinimapToggle`.
  minimap = {
    enabled = false,
    width = 14, -- columns, including the 1-column git gutter
    --- Text columns per braille dot column. At 3, 13 cells show 78 columns;
    --- 2 keeps the text's proportions but needs a wider map for the same span.
    columns_per_dot = 3,
    --- Colour each cell like the buffer text it covers (treesitter, else
    --- `:syntax`). Off draws the whole map in `ScrollMinimap`.
    colors = true,
    min_window_width = 80, -- not drawn in narrower windows
    --- The minimap is only drawn over ordinary file buffers ('buftype' empty),
    --- and never over these filetypes.
    excluded_filetypes = {
      "snacks_dashboard",
      "dashboard",
      "alpha",
      "ministarter",
      "starter",
      "lazy",
      "mason",
      "oil",
      "snacks_picker_list",
      "gitcommit",
    },
    --- `function(buf, win) -> boolean|nil`: decide per window. `nil` falls
    --- back to the rules above.
    enabled_for = nil,
    --- Underline the map row holding the cursor (`ScrollMinimapCursor`).
    cursor = true,
    --- Keep the minimap from hiding text.
    dodge = {
      --- Scroll sideways so the cursor never goes under the map, as if the
      --- window ended where the map starts. Only with 'nowrap'.
      margin = true,
      --- Hide the map while the cursor or a Visual selection is under it.
      hide = true,
    },
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
  hide_delay = 2500,

  winblend = 30, -- 0 = opaque, 100 = invisible

  --- Below the default float zindex (50) and well below the insert-completion
  --- popup (100, hard-coded in Neovim), so completion menus, LSP hover and
  --- notification windows all draw over the bar rather than under it. The bar
  --- still covers ordinary window text, which is what we want.
  zindex = 40,

  mouse = true,

  --- Touch screens that turn a finger drag into wheel events rather than a
  --- held-button drag, as Termux does. Over a vertical bar or the minimap,
  --- each wheel step then moves the thumb one row the way the finger went,
  --- instead of scrolling the content the opposite way.
  --- "auto" enables it inside Termux; true / false force it.
  touch = "auto",

  --- Scrollbar for file explorer sidebars. neo-tree and nvim-tree are ordinary
  --- windows and only need their filetype listed; the Snacks explorer draws
  --- only its visible rows, so it has its own adapter.
  explorer = {
    enabled = false,
    filetypes = { "neo-tree", "NvimTree" },
    snacks = true,
    --- Horizontal bar as well, for the tree windows above. Never for the
    --- Snacks list: it resets its own `leftcol` whenever it redraws, so a
    --- sideways position there would not survive the next scroll.
    horizontal = true,
    min_width = 10,
  },

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
local sections = { "vertical", "horizontal", "marks", "minimap", "explorer" }
local mark_sources = { "diagnostics", "git", "search", "scope" }

local function integer_at_least(min)
  return function(v)
    return type(v) == "number" and v == math.floor(v) and v >= min
  end
end

local function percent(v)
  return integer_at_least(0)(v) and v <= 100
end

local function cell(v)
  return type(v) == "string" and v ~= "" and vim.fn.strdisplaywidth(v) == 1
end

local function string_list(v)
  if type(v) ~= "table" or not vim.islist(v) then
    return false
  end
  for _, item in ipairs(v) do
    if type(item) ~= "string" then
      return false
    end
  end
  return true
end

local function severity_filter(v)
  local function severity(n)
    return type(n) == "number"
      and n == math.floor(n)
      and n >= vim.diagnostic.severity.ERROR
      and n <= vim.diagnostic.severity.HINT
  end
  if v == nil or severity(v) then
    return true
  end
  if type(v) ~= "table" or not vim.islist(v) then
    if type(v) ~= "table" then
      return false
    end
    for key in pairs(v) do
      if key ~= "min" and key ~= "max" then
        return false
      end
    end
    return (v.min == nil or severity(v.min)) and (v.max == nil or severity(v.max)) and (v.min ~= nil or v.max ~= nil)
  end
  for _, item in ipairs(v) do
    if not severity(item) then
      return false
    end
  end
  return #v > 0
end

local function bool(name, value)
  vim.validate(name, value, "boolean")
end

local function int(name, value, min)
  vim.validate(name, value, integer_at_least(min), ("an integer >= %d"):format(min))
end

local function glyph(name, value)
  vim.validate(name, value, cell, "a single-cell string")
end

--- Validate the complete public schema before any redraw can observe it.
--- @param opts table
local function validate(opts)
  bool("enabled", opts.enabled)
  vim.validate("vertical", opts.vertical, "table")
  bool("vertical.enabled", opts.vertical.enabled)
  int("vertical.width", opts.vertical.width, 1)
  glyph("vertical.char", opts.vertical.char)
  glyph("vertical.track_char", opts.vertical.track_char)

  vim.validate("horizontal", opts.horizontal, "table")
  bool("horizontal.enabled", opts.horizontal.enabled)
  int("horizontal.height", opts.horizontal.height, 1)
  glyph("horizontal.char", opts.horizontal.char)
  glyph("horizontal.track_char", opts.horizontal.track_char)

  vim.validate("visibility", opts.visibility, function(v)
    return v == "auto" or v == "always" or v == "hover"
  end, 'one of "auto", "always", "hover"')
  int("hide_delay", opts.hide_delay, 0)
  vim.validate("winblend", opts.winblend, percent, "an integer between 0 and 100")
  int("zindex", opts.zindex, 1)
  bool("mouse", opts.mouse)
  vim.validate("touch", opts.touch, function(v)
    return v == "auto" or type(v) == "boolean"
  end, 'true, false or "auto"')

  int("min_width", opts.min_width, 1)
  int("min_height", opts.min_height, 1)
  int("exact_measure_max_lines", opts.exact_measure_max_lines, 0)
  vim.validate("excluded_filetypes", opts.excluded_filetypes, string_list, "a list of strings")
  vim.validate("excluded_buftypes", opts.excluded_buftypes, string_list, "a list of strings")

  vim.validate("minimap", opts.minimap, "table")
  bool("minimap.enabled", opts.minimap.enabled)
  int("minimap.width", opts.minimap.width, 2)
  int("minimap.columns_per_dot", opts.minimap.columns_per_dot, 1)
  bool("minimap.colors", opts.minimap.colors)
  int("minimap.min_window_width", opts.minimap.min_window_width, 1)
  vim.validate("minimap.excluded_filetypes", opts.minimap.excluded_filetypes, string_list, "a list of strings")
  vim.validate("minimap.enabled_for", opts.minimap.enabled_for, "function", true)
  bool("minimap.cursor", opts.minimap.cursor)
  vim.validate("minimap.dodge", opts.minimap.dodge, "table")
  bool("minimap.dodge.margin", opts.minimap.dodge.margin)
  bool("minimap.dodge.hide", opts.minimap.dodge.hide)
  bool("minimap.git", opts.minimap.git)
  glyph("minimap.git_char", opts.minimap.git_char)
  vim.validate("minimap.winblend", opts.minimap.winblend, percent, "an integer between 0 and 100")
  bool("minimap.autohide", opts.minimap.autohide)

  vim.validate("explorer", opts.explorer, "table")
  bool("explorer.enabled", opts.explorer.enabled)
  vim.validate("explorer.filetypes", opts.explorer.filetypes, string_list, "a list of strings")
  bool("explorer.snacks", opts.explorer.snacks)
  bool("explorer.horizontal", opts.explorer.horizontal)
  int("explorer.min_width", opts.explorer.min_width, 1)

  vim.validate("marks", opts.marks, "table")
  bool("marks.enabled", opts.marks.enabled)
  for _, source in ipairs(mark_sources) do
    vim.validate("marks." .. source, opts.marks[source], "table")
    bool("marks." .. source .. ".enabled", opts.marks[source].enabled)
    glyph("marks." .. source .. ".char", opts.marks[source].char)
  end
  vim.validate(
    "marks.diagnostics.severity",
    opts.marks.diagnostics.severity,
    severity_filter,
    "a diagnostic severity, a non-empty list of severities, { min = severity }, { max = severity }, or nil"
  )
  int("marks.git.max_lines", opts.marks.git.max_lines, 0)
  int("marks.git.debounce", opts.marks.git.debounce, 0)
  vim.validate("marks.scope.node_types", opts.marks.scope.node_types, string_list, "a list of strings")

  local effective_min_width = math.max(opts.min_width, opts.minimap.min_window_width)
  local reserved = opts.minimap.width + (opts.vertical.enabled and opts.vertical.width or 0)
  if opts.minimap.enabled and effective_min_width <= reserved then
    error(
      ("minimap.width: minimap (%d) and vertical bar (%d) must fit inside eligible windows (minimum %d)"):format(
        opts.minimap.width,
        opts.vertical.enabled and opts.vertical.width or 0,
        effective_min_width
      )
    )
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
  vim.validate("opts", opts, "table", true)
  opts = vim.deepcopy(opts or {})
  for _, key in ipairs(sections) do
    expand(opts, key)
  end
  if type(opts.marks) == "table" then
    for _, key in ipairs(mark_sources) do
      expand(opts.marks, key)
    end
  end
  local merged = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts)
  validate(merged)
  M.options = merged
  return M.options
end

return M
