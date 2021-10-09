local assert = require('vgit.assertion').assert

local M = {}

M.state = {}

M.contains = function(buf)
  assert(type(buf) == 'number', 'type error :: expected number')
  return M.state[buf] ~= nil
end

M.add = function(buf)
  assert(type(buf) == 'number', 'type error :: expected number')
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
  assert(type(buf) == 'number', 'type error :: expected number')
  local bcache = M.state[buf]
  assert(bcache ~= nil, 'untracked buffer')
  M.state[buf] = nil
end

M.get = function(buf, key)
  assert(type(buf) == 'number', 'type error :: expected number')
  assert(type(key) == 'string', 'type error :: expected string')
  local bcache = M.state[buf]
  assert(bcache ~= nil, 'untracked buffer')
  return bcache[key]
end

M.set = function(buf, key, value)
  assert(type(buf) == 'number', 'type error :: expected number')
  assert(type(key) == 'string', 'type error :: expected string')
  local bcache = M.state[buf]
  assert(bcache ~= nil, 'untracked buffer')
  bcache[key] = value
end

M.for_each = function(fn)
  assert(type(fn) == 'function', 'type error :: expected function')
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
