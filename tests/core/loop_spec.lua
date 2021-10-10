local loop = require('vgit.core.loop')

local eq = assert.are.same

describe('loop', function()
  describe('throttle', function()
    local closure_creator = function(initial_value)
      local counter = initial_value
      return function()
        counter = counter + 1
        return counter
      end
    end

    it(
      'should not execute function more than once in the given time',
      function()
        local result = nil
        local closure = closure_creator(1)
        local throttled_fn = loop.throttle(function()
          result = closure()
          eq(result, 2)
        end, 100)
        for _ = 1, 1000 do
          throttled_fn()
        end
      end
    )

    it(
      'should throw errors if an error occurs within the wrapped function',
      function()
        local throttled_fn = loop.throttle(function()
          assert(false, 'an error has occured')
        end, 100)
        assert.has_error(function()
          for _ = 1, 1000 do
            throttled_fn()
          end
        end)
      end
    )
  end)

  describe('debounce_leading', function()
    local closure_creator = function(initial_value)
      local counter = initial_value
      return function()
        counter = counter + 1
        return counter
      end
    end

    it(
      'should not execute function more than once in the given time',
      function()
        local result = nil
        local closure = closure_creator(1)
        local debounced_fn = loop.debounce(function()
          result = closure()
          eq(result, 1)
        end, 100)
        for _ = 1, 1000 do
          debounced_fn()
        end
      end
    )
  end)

  describe('watch', function()
    it(
      'should watch for a file and execute callback if change is detected',
      function() end
    )
  end)
end)
