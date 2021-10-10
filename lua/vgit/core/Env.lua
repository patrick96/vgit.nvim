local Error = require('vgit.core.Error')
local Object = require('vgit.core.Object')

--[[
    Responsibility:
        Global store for values for the core.
--]]

local state = {}

local Env = Object:extend()

function Env:set(key, value)
  Error
    :assert_string(key)
    :assert_types(value, { 'string', 'number', 'boolean' })
  state[key] = value
  return Env
end

function Env:unset(key)
  Error:assert_string(key)
  Error:assert(state[key], 'error :: no value set for given key')
  state[key] = nil
  return Env
end

function Env:get(key)
  Error:assert_string(key)
  return state[key]
end

return Env
