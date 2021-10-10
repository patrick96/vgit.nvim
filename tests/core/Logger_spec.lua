local Logger = require('vgit.core.Logger')
local Env = require('vgit.core.Env')
local mock = require('luassert.mock')

local eq = assert.are.same

Env:set('DEBUG', true)

describe('Logger', function()
  describe('info', function()
    before_each(function()
      vim.notify = mock(vim.notify, true)
      vim.notify.returns(5)
    end)

    after_each(function()
      mock.revert(vim.notify)
    end)

    it('should call notify passing in the appropriate arguments', function()
      Logger:info('hello')
      assert.stub(vim.notify).was_called_with('hello', 'info')
    end)
  end)

  describe('warn', function()
    before_each(function()
      vim.notify = mock(vim.notify, true)
      vim.notify.returns(5)
    end)

    after_each(function()
      mock.revert(vim.notify)
    end)

    it('should call notify passing in the appropriate arguments', function()
      Logger:warn('hello')
      assert.stub(vim.notify).was_called_with('hello', 'warn')
    end)
  end)

  describe('error', function()
    before_each(function()
      vim.notify = mock(vim.notify, true)
      vim.notify.returns(5)
    end)

    after_each(function()
      mock.revert(vim.notify)
    end)

    it('should call notify passing in the appropriate arguments', function()
      Logger:error('hello')
      assert.stub(vim.notify).was_called_with('hello', 'error')
    end)
  end)

  describe('debug', function()
    it('should populate the logs when the debug flag is set to true', function()
      local count = 30
      for _ = 1, count do
        Logger:debug('stuff', debug.traceback())
      end
      eq(#Logger:get_logs(), count)
      Env:set('DEBUG', false)
      for _ = 1, count do
        Logger:debug('stuff', debug.traceback())
      end
      eq(#Logger:get_logs(), count)
    end)
  end)
end)
