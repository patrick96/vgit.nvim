local env = require('vgit.core.env')

local state = {
  logs = {},
}

local logger = {}

function logger.error(msg)
  vim.notify(msg, 'error')
  return logger
end

function logger.info(msg)
  vim.notify(msg, 'info')
  return logger
end

function logger.warn(msg)
  vim.notify(msg, 'warn')
  return logger
end

function logger.get_logs()
  return state.logs
end

function logger.debug(msg, trace)
  if not env.get('DEBUG') then
    return logger
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
  local logs = state.logs
  local log = ''
  if trace then
    log = string.format('VGit[%s]: %s\n%s', os.date('%H:%M:%S'), new_msg, trace)
  else
    log = string.format('VGit[%s]: %s', os.date('%H:%M:%S'), new_msg)
  end
  logs[#logs + 1] = log
  return logger
end

return logger
