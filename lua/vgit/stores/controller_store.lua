local M = {}

M.state = {
  config = {},
  disabled = false,
  hunks_enabled = true,
  blames_enabled = true,
  diff_strategy = 'index',
  diff_preference = 'horizontal',
  predict_hunk_signs = true,
  action_delay_ms = 300,
  predict_hunk_throttle_ms = 300,
  predict_hunk_max_lines = 50000,
  blame_line_throttle_ms = 150,
  use_internal_diff = false,
}

M.setup = function(config)
  vim.tbl_deep_extend('force', M.state, config and config.controller or {})
end

M.get = function(key)
  return M.state[key]
end

M.set = function(key, value)
  M.state[key] = value
end

return M
