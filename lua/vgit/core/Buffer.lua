local Object = require('vgit.core.Object')

local Buffer = Object:extend()

function Buffer:new(bufnr)
  if bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end
  return setmetatable({
    bufnr = bufnr,
  }, Buffer)
end

function Buffer:create(listed, scratch)
  listed = listed == nil and false or listed
  scratch = scratch == nil and false or scratch
  self.bufnr = vim.api.nvim_create_buf(listed, scratch)
  return self
end

function Buffer:is_current()
  return self.bufnr == vim.api.nvim_get_current_buf()
end

function Buffer:is_valid()
  local bufnr = self.bufnr
  return vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_is_loaded(bufnr)
end

function Buffer:delete(opts)
  opts = opts or {}
  vim.tbl_extend('keep', opts, { force = true })
  vim.api.nvim_buf_delete(self.bufnr, opts)
  return self
end

function Buffer:get_lines(start, finish)
  start = start or 0
  finish = finish or -1
  return vim.api.nvim_buf_get_lines(self.bufnr(), start, finish, false)
end

function Buffer:get_option(key)
  return vim.api.nvim_buf_get_option(self.bufnr(), key)
end

function Buffer:set_lines(lines, start, finish)
  start = start or 0
  finish = finish or -1
  local bufnr = self.bufnr()
  local modifiable = vim.api.nvim_buf_get_option(bufnr, 'modifiable')
  if modifiable then
    vim.api.nvim_buf_set_lines(bufnr, start, finish, false, lines)
    return
  end
  vim.api.nvim_buf_set_option(bufnr, 'modifiable', true)
  vim.api.nvim_buf_set_lines(bufnr, start, finish, false, lines)
  vim.api.nvim_buf_set_option(bufnr, 'modifiable', false)
  return self
end

function Buffer:set_option(key, value)
  vim.api.nvim_buf_set_option(self.bufnr(), key, value)
  return self
end

function Buffer:assign_options(options)
  local bufnr = self.bufnr()
  for key, value in pairs(options) do
    vim.api.nvim_buf_set_option(bufnr, key, value)
  end
end

function Buffer:get_line_count()
  return vim.api.nvim_buf_line_count(self.bufnr())
end

function Buffer:editing()
  return self:get_option('modified')
end

return Buffer
