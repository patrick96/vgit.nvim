local Env = require('vgit.core.Env')
local Object = require('vgit.core.Object')

local state = {
  logs = {},
}

local Logger = Object:extend()

function Logger:error(msg)
  vim.notify(msg, 'error')
  return Logger
end

function Logger:info(msg)
  vim.notify(msg, 'info')
  return Logger
end

function Logger:warn(msg)
  vim.notify(msg, 'warn')
  return Logger
end

function Logger:get_logs()
  return state.logs
end

function Logger:debug(msg, trace)
  if not Env:get('DEBUG') then
    return Logger
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
  return Logger
end

return Logger
