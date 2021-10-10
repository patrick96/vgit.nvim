local Object = require('vgit.core.Object')

local Window = Object:extend()

function Window:new(win_id)
  return setmetatable({
    win_id = win_id,
  }, Window)
end

function Window:open(buffer, opts)
  opts = opts or {}
  local focus = opts.focus
  if opts.focus then
    opts.focus = nil
  end
  self.win_id = vim.api.nvim_open_win(
    buffer.bufnr,
    focus ~= nil and focus or false,
    opts
  )
  return self
end

return Window
