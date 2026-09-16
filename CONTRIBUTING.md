# Contributing

Bug reports, ideas and pull requests are welcome.

## Reporting a bug

Please include:

- `nvim --version` and your OS and terminal (glyph rendering differs between terminals and fonts);
- your `setup()` options, if any;
- the smallest steps that reproduce it, ideally starting from `nvim --clean` with only this plugin
  loaded:

  ```sh
  nvim --clean --cmd "set rtp+=/path/to/scroll.nvim"
  ```

- a screenshot for anything visual.

## Development

Requires Neovim 0.11+. Point your plugin manager at a local checkout, for example with lazy.nvim:

```lua
{ dir = "~/src/scroll.nvim", name = "scroll.nvim" }
```

Run the tests before sending a pull request:

```sh
make test                        # all suites, headless, independent of your config
make test-integration            # a single suite
make test NVIM_BIN=/path/to/nvim # a specific Neovim build
```

Format with [StyLua](https://github.com/JohnnyMorganz/StyLua) (`make fmt`), using the repository's
`.stylua.toml`.

## Pull requests

- Keep each pull request to one change, and add or update a test in `tests/` for behaviour changes.
- Refreshes run on every scroll event, so avoid work that grows with buffer size on that path. The
  `measure` and `ruler` suites print timings; mention any change in them.
- Update `README.md` and `doc/scroll.txt` when options or commands change.
- Add a line under **Unreleased** in `CHANGELOG.md`.

## Releases

Versions follow [Semantic Versioning](https://semver.org). To release:

1. Move the **Unreleased** entries in `CHANGELOG.md` under a new version heading with today's date,
   and update the comparison links at the bottom.
2. Commit, then tag and push:

   ```sh
   git tag -a v0.2.0 -m "v0.2.0"
   git push origin main v0.2.0
   ```

3. Create a GitHub release from the tag, using the changelog section as its notes.
