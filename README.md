# scroll.nvim

VS Code-style scrollbars for Neovim, **vertical and horizontal** overlaid on the window edges,
draggable with the mouse, and auto-hiding when idle. The vertical track doubles as an **overview
ruler**, marking diagnostics, git changes and search matches across the whole buffer, and an
optional **minimap** shows the buffer's shape in its syntax colours, with a git change gutter.

Neovim has no built-in scrollbar, and while `nvim-scrollview` covers the vertical case, nothing
provides a horizontal one. With `wrap` off, the only cue that a line runs past the right edge is the
cursor bumping into it. This plugin fixes both.

Requires Neovim **0.11+**.

## Install

Installing is all it takes: the plugin sets itself up with the defaults, so no `setup()` call is
needed unless you want to change something.

**[lazy.nvim](https://github.com/folke/lazy.nvim)** (also LazyVim): add a file such as
`lua/plugins/scroll.lua`:

```lua
return { "mihovilrak/scroll.nvim" }
```

To change options, add `opts`; lazy.nvim passes them to `require("scroll").setup()`:

```lua
return {
  "mihovilrak/scroll.nvim",
  opts = { minimap = true },
}
```

Add `version = "*"` to follow tagged releases instead of the latest commit.

**Neovim 0.12+ built-in `vim.pack`:**

```lua
vim.pack.add({ "https://github.com/mihovilrak/scroll.nvim" })
```

**[mini.deps](https://github.com/echasnovski/mini.nvim):**

```lua
MiniDeps.add({ source = "mihovilrak/scroll.nvim" })
```

**No plugin manager:** clone it into a package directory and call `setup()` from your config:

```sh
# Linux / macOS
git clone https://github.com/mihovilrak/scroll.nvim ~/.local/share/nvim/site/pack/plugins/start/scroll.nvim
# Windows (PowerShell)
git clone https://github.com/mihovilrak/scroll.nvim "$env:LOCALAPPDATA\nvim-data\site\pack\plugins\start\scroll.nvim"
```

Mouse support needs `vim.o.mouse` to include normal mode (`"a"`, Neovim's default).

## Configuration

`setup()` takes the table below; anything you omit keeps its default, and calling it again replaces
the options. The `vertical`, `horizontal`, `marks` and `minimap` sections, and each source under
`marks`, also accept a bare boolean: `minimap = true` is short for `minimap = { enabled = true }`.
For example, to turn on the minimap, drop git marks and only mark warnings and errors:

```lua
require("scroll").setup({
  minimap = true,
  marks = {
    git = false,
    diagnostics = { severity = { min = vim.diagnostic.severity.WARN } },
  },
})
```

With lazy.nvim, put the same table in `opts`. The full set of options and their defaults:

```lua
require("scroll").setup({
  enabled = true,

  vertical = {
    enabled = true,
    width = 1,           -- track width in columns
    char = "█",          -- thumb glyph
    track_char = "│",    -- track glyph; " " for an invisible track
  },
  horizontal = {
    enabled = true,
    height = 1,
    char = "▄",          -- half a cell: as thick as the 1-column vertical thumb
    track_char = "─",
  },

  visibility = "auto",   -- "auto" | "always" | "hover"
  hide_delay = 1000,     -- ms of quiet before hiding, when visibility = "auto"

  -- Overview ruler: ticks on the vertical track. Git changes take the track's left
  -- column and everything else its right; on a 1-column track they share it and
  -- the most severe wins (error > warning > search > info > hint > git).
  marks = {
    enabled = true,
    diagnostics = {
      enabled = true,
      char = "━",
      severity = nil,    -- passed to vim.diagnostic.get, e.g. { min = vim.diagnostic.severity.WARN }
    },
    git = {
      enabled = true,
      char = "▌",
      max_lines = 20000, -- without gitsigns: skip the index diff above this size
      debounce = 200,    -- without gitsigns: ms after an edit before re-diffing
    },
    search = {
      enabled = true,
      char = "━",        -- shown while 'hlsearch' is highlighting @/
    },
  },

  -- Braille minimap, overlaid left of the vertical bar. Off by default.
  minimap = {
    enabled = false,
    width = 14,             -- columns, including the 1-column git gutter
    columns_per_dot = 3,    -- text columns per braille dot column
    colors = true,          -- colour cells like the buffer text; false = all ScrollMinimap
    min_window_width = 80,  -- not drawn in narrower windows
    git = true,             -- git change gutter
    git_char = "▎",
    winblend = 0,
    autohide = false,       -- hide along with the scrollbars under `visibility`
  },

  winblend = 30,         -- 0 = opaque, 100 = invisible
  zindex = 40,           -- below completion popups, above window text
  mouse = true,          -- click-to-jump and thumb dragging

  excluded_filetypes = { "help", "qf", "NvimTree", "neo-tree", "TelescopePrompt", "lazy", "mason" },
  excluded_buftypes = { "terminal", "prompt", "nofile", "quickfix" },

  min_width = 20,        -- skip windows narrower than this
  min_height = 5,

  exact_measure_max_lines = 10000,
})
```

`visibility = "hover"` needs `vim.o.mousemoveevent = true` to receive pointer motion.

### Highlights

`ScrollTrack`, `ScrollThumb` and `ScrollThumbHover`, linked by default to `PmenuSbar` / `PmenuThumb`
so they follow your colorscheme. The thumb glyph is drawn in `ScrollThumb`'s foreground (or
`Normal`'s, when it has none) over the track's background, so the half-block horizontal thumb really
is half a cell.

Ruler marks: `ScrollMarkError` / `Warn` / `Info` / `Hint` (linked to the `Diagnostic*` groups),
`ScrollMarkAdd` / `Change` / `Delete` (linked to `GitSigns*` when your colorscheme styles them, else
`Added` / `Changed` / `Removed`), and `ScrollMarkSearch` (the background colour of `Search`, used as
a foreground).

Minimap: `ScrollMinimap` (linked to `NormalFloat`) and `ScrollMinimapViewport` (linked to `Visual`).
With `minimap.colors`, the dots use the buffer's own highlight groups instead of `ScrollMinimap`.

All are defined with `default = true`, so your own `:highlight` wins and survives a `ColorScheme`
change.

### Git

With [gitsigns.nvim](https://github.com/lewis6991/gitsigns.nvim) attached to a buffer, its hunks are
used directly. Without it, the plugin fetches the file's index version once with `git show` and
diffs the live buffer against it, so unsaved edits are marked too. The index copy is refreshed on
write and when Neovim regains focus.

### Minimap

Each braille cell covers 4 buffer lines and `2 * columns_per_dot` text columns; a dot is lit when its
block contains any non-blank character. The defaults (14 columns, 3 per dot) show the first 78 text
columns; `columns_per_dot = 2` keeps the text's proportions but needs about `width = 20` for the same
span. With `colors` on, each cell takes the highlight group covering most of its text, from
treesitter when it is highlighting the buffer and from `:syntax` otherwise. Folds and wrapping are
ignored. The map scrolls in proportion to the window, the visible region is
highlighted, and clicking or dragging on it centres the window on that spot. The horizontal
scrollbar stops where the minimap begins.

Only the rows on screen are rendered (about `4 * height` lines per refresh, whatever the buffer
size), and rendered rows are cached until the buffer changes. After an edit, treesitter reparses in
the background; until it finishes, colours come from the previous parse.

### Commands

`:ScrollToggle`, `:ScrollEnable`, `:ScrollDisable`, `:ScrollRefresh`, `:ScrollMinimapToggle`.
`require("scroll").toggle_minimap(on?)` does the same from Lua.

## How it works

Bars are **floating windows**, one per bar per window. Extmarks would have been simpler, but they
are buffer-scoped: one buffer shown in two splits would draw both windows' bars into both. Floats
are window-scoped and correct. They are created once and thereafter only reconfigured, and
auto-hide toggles the `hide` window flag rather than closing them, so there is no window churn and
no flicker.

The interesting problem is measuring a document cheaply enough to do it on every scroll event.

**Vertically**, `nvim_win_text_height` is the only call that correctly accounts for folds, wrapping,
virtual lines, diff filler and `'smoothscroll'`, but measuring from the start of the buffer is
O(topline), about 14 ms halfway down a 100k-line wrapped buffer. Instead the plugin exploits an
additivity identity (`start_vcol = 0` makes adjacent ranges telescope rather than double-count) to
maintain the offset incrementally, moving it by the distance actually scrolled. That is **0.024 ms
per scroll step** on the same buffer, and `tests/measure_spec.lua` checks it against ground truth at
every step. When the buffer renders one row per line, the plugin detects that by observing
`total == line_count` and skips the measurement entirely.

**Horizontally**, the expensive quantity is the widest line. A full `strdisplaywidth` scan of 100k
lines costs ~73 ms, so it runs in chunks off a timer while the visible lines (always cheap) are
measured synchronously, meaning the bar is never blank while a scan is in flight. The cached width
is only published when a scan completes, which is what stops the thumb jittering as you type.

Refreshes are coalesced: events set a dirty flag and schedule one pass via `vim.schedule`, so the
several events a single keystroke fires collapse into one redraw with no added latency.

**Ruler marks** do not move when you scroll, so their track rows are computed only when the marks or
the document change, and every scroll-driven redraw reuses them. Row placement uses the same
telescoping measurement as the thumb, so marks stay exact across folds and wrapped lines. Updates
that arrive in the background (an LSP publishing diagnostics, a finished search scan) redraw only
bars already on screen, so they never pop the bars up while you are reading. Search matching is
O(lines), so large buffers are scanned in chunks off a timer, like the width scan.

## Development

To try a local checkout with lazy.nvim, point `dir` at it:

```lua
{ dir = "~/src/scroll.nvim", name = "scroll.nvim", opts = {} }
```

Run the tests with:

```sh
make test
```

Six suites, all headless and independent of your config:

- `geometry_spec`: the pure thumb math, including an exhaustive sweep asserting the thumb never
  leaves its track and never inverts.
- `measure_spec`: incremental measurement against ground truth on wrapped and folded buffers, plus
  a performance regression guard.
- `width_spec`: the document-width cache and its background scan.
- `integration_spec`: real windows and floats: splits sharing a buffer, winbar offsets, gutters,
  folds, floats, excluded buffers.
- `ruler_spec`: mark placement, priority and lanes, each source (the git fallback runs against a
  throwaway repository), fold changes, and a guard that scrolling does not re-place marks.
- `minimap_spec`: braille encoding, map layout, the float and its viewport and git gutter, and
  that drag-scrolling keeps its position under any `'scrolloff'`.

Inside a Neovim `:terminal`, `$NVIM` is the server address, so the Makefile uses `NVIM_BIN` to pick
the binary: `make test NVIM_BIN=/path/to/nvim`. `make fmt` formats with
[StyLua](https://github.com/JohnnyMorganz/StyLua).

## Changelog

See [CHANGELOG.md](CHANGELOG.md). Releases are tagged with [semantic versions](https://semver.org).
Contributions are welcome; see [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE) © 2026 Mihovil Rak
