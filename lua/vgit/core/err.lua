local err = {}

function err.assert(cond, msg)
  if not cond then
    error(debug.traceback(msg))
  end
  return err
end

function err.assert_type(value, t)
  err.assert(type(value) == t, string.format('type error :: expected %s', t))
  return err
end

function err.assert_types(value, types)
  err.assert_list(types)
  local passed = false
  for i = 1, #types do
    local t = types[i]
    if type(value) == t then
      passed = true
    end
  end
  err.assert(
    passed,
    string.format('type error :: expected %s', vim.inspect(types))
  )
  return err
end

function err.assert_number(value)
  err.assert_type(value, 'number')
  return err
end

function err.assert_string(value)
  err.assert_type(value, 'string')
  return err
end

function err.assert_function(value)
  err.assert_type(value, 'function')
  return err
end

function err.assert_boolean(value)
  err.assert_type(value, 'boolean')
  return err
end

function err.assert_nil(value)
  err.assert_type(value, 'nil')
  return err
end

function err.assert_table(value)
  err.assert_type(value, 'table')
  return err
end

function err.assert_list(value)
  err.assert(vim.tbl_islist(value), 'type error :: expected list')
  return err
end

return err
