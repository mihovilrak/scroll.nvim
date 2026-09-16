.PHONY: test test-geometry test-measure test-width test-integration test-ruler fmt

# Not `NVIM`: Nvim exports that as its server address inside `:terminal`.
NVIM_BIN ?= nvim

# All suites run in a headless Nvim with no user config, so results do not
# depend on whatever plugins happen to be installed.
test: test-geometry test-measure test-width test-integration test-ruler

test-geometry:
	@$(NVIM_BIN) --headless -u NONE -l tests/geometry_spec.lua

test-measure:
	@$(NVIM_BIN) --headless -u NONE -l tests/measure_spec.lua

test-width:
	@$(NVIM_BIN) --headless -u NONE -l tests/width_spec.lua

test-integration:
	@$(NVIM_BIN) --headless -u NONE -l tests/integration_spec.lua

test-ruler:
	@$(NVIM_BIN) --headless -u NONE -l tests/ruler_spec.lua

fmt:
	@stylua lua/ tests/
