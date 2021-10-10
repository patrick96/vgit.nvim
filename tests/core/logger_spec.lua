local logger = require('vgit.core.logger')
local env = require('vgit.core.env')
local mock = require('luassert.mock')

local eq = assert.are.same

env.set('DEBUG', true)

describe('logger', function()
  describe('info', function()
    before_each(function()
      vim.notify = mock(vim.notify, true)
      vim.notify.returns(5)
    end)

    after_each(function()
      mock.revert(vim.notify)
    end)

    it('should call notify passing in the appropriate arguments', function()
      logger.info('hello')
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
      logger.warn('hello')
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
      logger.error('hello')
      assert.stub(vim.notify).was_called_with('hello', 'error')
    end)
  end)

  describe('debug', function()
    it('should populate the logs when the debug flag is set to true', function()
      local count = 30
      for _ = 1, count do
        logger.debug('stuff', debug.traceback())
      end
      eq(#logger.get_logs(), count)
      env.set('DEBUG', false)
      for _ = 1, count do
        logger.debug('stuff', debug.traceback())
      end
      eq(#logger.get_logs(), count)
    end)
  end)
end)
