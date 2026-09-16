.PHONY: test test-geometry test-measure test-width test-integration fmt

NVIM ?= nvim

# All suites run in a headless Nvim with no user config, so results do not
# depend on whatever plugins happen to be installed.
test: test-geometry test-measure test-width test-integration

test-geometry:
	@$(NVIM) --headless -u NONE -l tests/geometry_spec.lua

test-measure:
	@$(NVIM) --headless -u NONE -l tests/measure_spec.lua

test-width:
	@$(NVIM) --headless -u NONE -l tests/width_spec.lua

test-integration:
	@$(NVIM) --headless -u NONE -l tests/integration_spec.lua

fmt:
	@stylua lua/ tests/
