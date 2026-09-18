# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). Until 1.0.0, a minor version may change
defaults or options; such changes are listed under **Changed**.

## [0.4.0] - 2026-09-18

### Added

- `explorer.horizontal` (on by default): neo-tree and nvim-tree sidebars get a horizontal bar as
  well as a vertical one, when a name runs past the sidebar's edge. The Snacks explorer is left
  out: its list resets its own `leftcol` every time it redraws, so a sideways position there would
  not survive the next scroll.

### Fixed

- The Snacks explorer's list scrolled the wrong way under the mouse wheel and could never reach the
  top -- the bug 0.3.1 and 0.3.2 were aimed at, which neither actually fixed. The cause was not the
  bar at all: merely *having* a `<ScrollWheelUp>` mapping breaks scrolling inside a Snacks picker
  list, even though Snacks swallows the wheel in `vim.on_key` before the mapping layer runs and the
  mapping never fires. With one registered, every wheel event costs the list an extra `CursorMoved`
  round-trip, so `list:_move` re-applies its `'scrolloff'` clamp once more than it should and drags
  the list back further than the wheel moved it. An empty
  `vim.keymap.set("n", "<ScrollWheelUp>", function() end)` reproduces it with no plugin loaded. The
  wheel is no longer mapped: it is watched with `vim.on_key` and claimed only when the pointer is
  actually over a bar, so anywhere else Nvim behaves exactly as if the plugin were not loaded.
- A click on a window separator no longer grabs the vertical scrollbar, so dragging the separator
  resizes the split again. `getwininfo()` reports a width that excludes the separator while
  `getmousepos()` places a click on it at that same column in the window to its left, and the hit
  test bounded the column from below only.

### Changed

- The mouse wheel is no longer mapped, so your own `<ScrollWheelUp>`/`<ScrollWheelDown>` mappings
  now run untouched instead of being captured and replayed.

## [0.3.2] - 2026-09-17

### Fixed

- The Snacks explorer's scrollbar thumb could still lag behind the list after 0.3.1, most visibly
  getting stuck short of the top. 0.3.1 only refreshed it on a drag or a wheel scroll directly over
  the bar's own thin strip. A wheel scroll over the list body itself, the common case, never
  reached our `<ScrollWheelUp/Down>` mapping at all, because Snacks intercepts the wheel at the
  `vim.on_key` level, before Nvim's mapping layer runs, and swallows it outright on Nvim 0.11+. A
  `vim.on_key` watcher now catches the same event Snacks does and nudges a refresh once its own
  scroll has run.

## [0.3.1] - 2026-09-17

### Fixed

- The Snacks explorer's scrollbar thumb could lag behind the list, most visibly getting stuck short
  of the top: the explorer scrolls by rewriting its list, which fires no event the bar can react to,
  so with nothing else in the tabpage generating a refresh it only caught up on the next idle
  `SafeState` poll. Dragging or wheel-scrolling the explorer's bar now refreshes it immediately, and
  a wheel scroll over the list itself nudges a refresh instead of waiting on `SafeState`.

## [0.3.0] - 2026-09-17

### Added

- `marks.scope` (on by default): ticks on the vertical track at the first and last line of the
  function, `if`, loop or similar block around the cursor, found with treesitter.
- `minimap.cursor` (on by default): the minimap row holding the cursor is underlined
  (`ScrollMinimapCursor`).
- `minimap.dodge`: with `'nowrap'` the view scrolls sideways so the cursor never goes under the
  minimap (`margin`), and the minimap hides while the cursor or a Visual selection is under it
  (`hide`).
- `minimap.excluded_filetypes` and `minimap.enabled_for`, to choose which windows get a minimap.
- `explorer` (off by default): a vertical scrollbar for the Snacks explorer, neo-tree and nvim-tree.
- The mouse wheel over the minimap or a scrollbar scrolls the window underneath.

### Changed

- `hide_delay` 1000 -> 2500 ms, so the bars are still there when your hand reaches the mouse.
- The minimap is only drawn over ordinary file buffers ('buftype' empty).

### Fixed

- The minimap stayed on windows that turned into a terminal after they opened, as Snacks terminals
  do. Windows that stop being eligible now lose their bars on the next refresh.
- The minimap and the scrollbar went out of sync after a mouse-wheel scroll over them: the wheel
  scrolled the bar's own float. It now scrolls the window, and a scrolled float is put back.
- A lost mouse release no longer leaves an old drag steering the next click.

## [0.2.0] - 2026-09-16

### Added

- `minimap.colors` (on by default): the minimap takes the buffer's treesitter or `:syntax` colours.

### Changed

- The minimap is narrower by default: `width` 20 -> 14 and `columns_per_dot` 2 -> 3, so it still
  shows the first 78 text columns. Set `width = 20, columns_per_dot = 2` for the old look.

### Fixed

- Ruler marks on the thumb no longer erase it: a git mark now covers only half the cell, and the
  thumb shows in the other half.

## [0.1.0] - 2026-09-16

First release.

### Added

- Vertical and horizontal scrollbars drawn as floating windows over the window edges, correct for
  one buffer shown in several splits.
- Click-to-jump and thumb dragging with the mouse.
- `visibility = "auto" | "always" | "hover"`, with auto-hide after `hide_delay`.
- Exact vertical measurement across folds, wrapping, virtual lines and `'smoothscroll'`, kept
  incrementally so a scroll step costs a fraction of a millisecond on 100k-line buffers.
- Document-width scanning in the background for the horizontal bar.
- Overview ruler on the vertical track: diagnostics, git changes (from gitsigns.nvim, or a built-in
  diff against the index) and search matches.
- Optional braille minimap with a git change gutter, click and drag to scroll, and
  `:ScrollMinimapToggle`.
- `:ScrollToggle`, `:ScrollEnable`, `:ScrollDisable`, `:ScrollRefresh` and a Lua API.
- The plugin sets itself up with the defaults; `setup()` is only needed to change options, and can
  be called again to replace them.
- Boolean shorthand for option sections: `minimap = true`, `marks = { git = false }`.
- A box-drawing joint (`┘`) where the vertical and horizontal tracks meet.
- `:help scroll`, headless test suites and CI on Neovim 0.11, stable and nightly.

[Unreleased]: https://github.com/mihovilrak/scroll.nvim/compare/v0.4.0...HEAD
[0.4.0]: https://github.com/mihovilrak/scroll.nvim/compare/v0.3.2...v0.4.0
[0.3.2]: https://github.com/mihovilrak/scroll.nvim/compare/v0.3.1...v0.3.2
[0.3.1]: https://github.com/mihovilrak/scroll.nvim/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/mihovilrak/scroll.nvim/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/mihovilrak/scroll.nvim/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/mihovilrak/scroll.nvim/releases/tag/v0.1.0
