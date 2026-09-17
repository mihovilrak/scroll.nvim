# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). Until 1.0.0, a minor version may change
defaults or options; such changes are listed under **Changed**.

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

[Unreleased]: https://github.com/mihovilrak/scroll.nvim/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/mihovilrak/scroll.nvim/releases/tag/v0.1.0
