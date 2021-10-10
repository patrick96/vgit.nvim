local M = {}

M.state = {
  debug = false,
  debug_logs = {},
}

M.setup = function(config)
  vim.tbl_deep_extend('force', M.state, config and config.logger or {})
end

M.error = function(msg)
  vim.notify(msg, 'error')
end

M.info = function(msg)
  vim.notify(msg, 'info')
end

M.warn = function(msg)
  vim.notify(msg, 'warn')
end

M.debug = function(msg, trace)
  if not M.state.debug then
    return
  end
  local new_msg = ''
  if vim.tbl_islist(msg) then
    for i = 1, #msg do
      local m = msg[i]
      if i == 1 then
        new_msg = new_msg .. m
      else
        new_msg = new_msg .. ', ' .. m
      end
    end
  else
    new_msg = msg
  end
  local debug_logs = M.state.debug_logs
  local log = ''
  if trace then
    log = string.format('VGit[%s]: %s\n%s', os.date('%H:%M:%S'), new_msg, trace)
  else
    log = string.format('VGit[%s]: %s', os.date('%H:%M:%S'), new_msg)
  end
  debug_logs[#debug_logs + 1] = log
end

return M
