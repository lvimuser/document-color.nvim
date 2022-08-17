local M = {}

--- Debounces a function on the trailing edge. Automatically
--- `schedule_wrap()`s.
---
---@param fn function Function to debounce
---@param duration number Timeout in ms
---@return unknown timer, function wrapped_fn Timer and debounced function.
---Remember to call -`timer:close()` at the end or you will leak memory!
function M.debounce(fn, duration)
  local timer = vim.loop.new_timer()
  local function inner(...)
    local argv = { ... }
    timer:start(
      duration,
      0,
      vim.schedule_wrap(function()
        fn(unpack(argv))
      end)
    )
  end

  return timer, inner
end

return M
