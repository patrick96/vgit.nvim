local uv = vim.loop

--[[
    Responsibility:
        One stop shop for all things asynchronous.
--]]

local loop = {}

function loop.throttle(fn, ms)
  local timer = vim.loop.new_timer()
  local running = false
  return function(...)
    if running then
      return
    end
    timer:start(ms, 0, function()
      running = false
    end)
    running = true
    fn(...)
  end
end

function loop.debounce(fn, ms)
  local timer = vim.loop.new_timer()
  return function(...)
    local argv = { ... }
    local argc = select('#', ...)
    timer:start(ms, 0, function()
      fn(unpack(argv, 1, argc))
    end)
  end
end

function loop.watch(filename, callback)
  local watcher = uv.new_fs_event()
  local function on_change()
    callback(filename)
    watcher:stop()
    loop.watch(filename, callback)
  end
  local fullpath = vim.api.nvim_call_function('fnamemodify', { filename, ':p' })
  watcher:start(
    fullpath,
    {},
    vim.schedule_wrap(function()
      on_change()
    end)
  )
end

return loop
