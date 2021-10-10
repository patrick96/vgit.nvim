local M = {}

M.state = {
  current = {},
}

M.get = function()
  return M.state.current
end

M.set = function(component)
  M.state.current = component
end

M.exists = function()
  return not vim.tbl_isempty(M.get())
end

M.clear = function()
  M.state.current = {}
end

return M
