local M = {}

M.retrieve = function(cmd, ...)
  if type(cmd) == 'function' then
    return cmd(...)
  end
  return cmd
end

M.round = function(x)
  return x >= 0 and math.floor(x + 0.5) or math.ceil(x - 0.5)
end

return M
