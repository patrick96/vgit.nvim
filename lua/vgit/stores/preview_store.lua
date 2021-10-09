local M = {}

M.state = {
  current = {},
}

M.get = function()
  return M.state.current
end

M.set = function(component)
  assert(type(component) == 'table', 'type error :: expected table')
  M.state.current = component
end

M.exists = function()
  return not vim.tbl_isempty(M.get())
end

M.clear = function()
  if M.exists() then
    M.get():unmount()
    M.state.current = {}
  end
end

return M
