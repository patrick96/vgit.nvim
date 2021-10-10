local Object = require('vgit.core.Object')

local Error = Object:extend()

function Error:assert(cond, msg)
  if not cond then
    error(debug.traceback(msg))
  end
  return Error
end

function Error:assert_type(value, t)
  Error:assert(type(value) == t, string.format('type error :: expected %s', t))
  return Error
end

function Error:assert_types(value, types)
  Error:assert_list(types)
  local passed = false
  for i = 1, #types do
    local t = types[i]
    if type(value) == t then
      passed = true
    end
  end
  Error:assert(
    passed,
    string.format('type error :: expected %s', vim.inspect(types))
  )
  return Error
end

function Error:assert_number(value)
  Error:assert_type(value, 'number')
  return Error
end

function Error:assert_string(value)
  Error:assert_type(value, 'string')
  return Error
end

function Error:assert_function(value)
  Error:assert_type(value, 'function')
  return Error
end

function Error:assert_boolean(value)
  Error:assert_type(value, 'boolean')
  return Error
end

function Error:assert_nil(value)
  Error:assert_type(value, 'nil')
  return Error
end

function Error:assert_table(value)
  Error:assert_type(value, 'table')
  return Error
end

function Error:assert_list(value)
  Error:assert(vim.tbl_islist(value), 'type error :: expected list')
  return Error
end

return Error
