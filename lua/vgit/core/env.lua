local err = require('vgit.core.err')

--[[
    Responsibility:
        Global store for values for the core.
--]]

local state = {}

local env = {}

function env.set(key, value)
  err.assert_string(key).assert_types(value, { 'string', 'number', 'boolean' })
  state[key] = value
  return env
end

function env.unset(key)
  err.assert_string(key)
  err.assert(state[key], 'error :: no value set for given key')
  state[key] = nil
  return env
end

function env.get(key)
  err.assert_string(key)
  return state[key]
end

return env
