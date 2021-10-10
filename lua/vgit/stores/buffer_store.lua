local M = {}

M.state = {}

M.contains = function(buf)
  return M.state[buf] ~= nil
end

M.add = function(buf)
  M.state[buf] = {
    filename = '',
    filetype = '',
    tracked_filename = '',
    tracked_remote_filename = '',
    logs = {},
    hunks = {},
    blames = {},
    disabled = false,
    last_lnum_blamed = 1,
    temp_lines = {},
    untracked = false,
  }
end

M.remove = function(buf)
  M.state[buf] = nil
end

M.get = function(buf, key)
  local bcache = M.state[buf]
  return bcache[key]
end

M.set = function(buf, key, value)
  local bcache = M.state[buf]
  bcache[key] = value
end

M.for_each = function(fn)
  for key, value in pairs(M.state) do
    fn(key, value)
  end
end

M.get_data = function()
  return M.state.data
end

M.size = function()
  return #M.state.data
end

return M
