--- Minimal test harness, so the suite runs with plain `nvim -l` and needs no
--- plugin manager or test framework installed.
local M = { failures = 0, checks = 0, current = nil }

function M.describe(name, fn)
  M.current = name
  local ok, err = pcall(fn)
  if not ok then
    M.failures = M.failures + 1
    io.write(string.format("  ERROR in %s: %s\n", name, err))
  end
  M.current = nil
end

function M.check(cond, msg)
  M.checks = M.checks + 1
  if not cond then
    M.failures = M.failures + 1
    io.write(string.format("  FAIL [%s] %s\n", M.current or "?", msg))
  end
end

function M.eq(got, want, msg)
  M.check(got == want, string.format("%s (got %s, want %s)", msg, tostring(got), tostring(want)))
end

--- Print the summary and exit non-zero if anything failed.
function M.finish(suite)
  if M.failures == 0 then
    io.write(string.format("%s: %d checks passed\n", suite, M.checks))
    os.exit(0)
  end
  io.write(string.format("%s: %d FAILED of %d checks\n", suite, M.failures, M.checks))
  os.exit(1)
end

return M
