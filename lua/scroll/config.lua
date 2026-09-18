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
  vim.validate("minimap.colors", opts.minimap.colors, "boolean")
  vim.validate("minimap.columns_per_dot", opts.minimap.columns_per_dot, function(v)
    return type(v) == "number" and v >= 1
  end, "a number >= 1")
  vim.validate("minimap.enabled_for", opts.minimap.enabled_for, "function", true)
  vim.validate("minimap.dodge", opts.minimap.dodge, "table")
  vim.validate("explorer", opts.explorer, "table")
  vim.validate("explorer.horizontal", opts.explorer.horizontal, "boolean")
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
