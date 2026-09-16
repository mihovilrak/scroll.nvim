# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). Until 1.0.0, a minor version may change
defaults or options; such changes are listed under **Changed**.

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
