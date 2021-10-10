local utils = require('vgit.utils')
local render_store = require('vgit.stores.render_store')

local M = {}

M.constants = {
  ns_id = 'tanvirtin/vgit.nvim/hunk/signs',
}

M.state = {
  VGitViewSignAdd = {
    name = render_store.get('preview').sign.hls.add,
    line_hl = render_store.get('preview').sign.hls.add,
    text_hl = nil,
    num_hl = nil,
    icon = nil,
    text = '',
  },
  VGitViewSignRemove = {
    name = render_store.get('preview').sign.hls.remove,
    line_hl = render_store.get('preview').sign.hls.remove,
    text_hl = nil,
    num_hl = nil,
    icon = nil,
    text = '',
  },
  VGitSignAdd = {
    name = render_store.get('sign').hls.add,
    text_hl = render_store.get('sign').hls.add,
    num_hl = nil,
    icon = nil,
    line_hl = nil,
    text = '┃',
  },
  VGitSignRemove = {
    name = render_store.get('sign').hls.remove,
    text_hl = render_store.get('sign').hls.remove,
    num_hl = nil,
    icon = nil,
    line_hl = nil,
    text = '┃',
  },
  VGitSignChange = {
    name = render_store.get('sign').hls.change,
    text_hl = render_store.get('sign').hls.change,
    num_hl = nil,
    icon = nil,
    line_hl = nil,
    text = '┃',
  },
}

M.setup = function(config)
  vim.tbl_deep_extend('force', M.state, (config and config.signs) or {})
  for _, action in pairs(M.state) do
    M.define(action)
  end
end

M.define = function(config)
  vim.fn.sign_define(config.name, {
    text = config.text,
    texthl = config.text_hl,
    numhl = config.num_hl,
    icon = config.icon,
    linehl = config.line_hl,
  })
end

M.place = function(buf, lnum, type, priority)
  vim.fn.sign_place(
    lnum,
    string.format('%s/%s', M.constants.ns_id, buf),
    type,
    buf,
    {
      id = lnum,
      lnum = lnum,
      priority = priority,
    }
  )
end

M.unplace = function(buf)
  vim.fn.sign_unplace(string.format('%s/%s', M.constants.ns_id, buf))
end

M.get = function(buf, lnum)
  local signs = vim.fn.sign_getplaced(buf, {
    group = string.format('%s/%s', M.constants.ns_id, buf),
    id = lnum,
  })[1].signs
  local result = {}
  for i = 1, #signs do
    local sign = signs[i]
    result[i] = sign.name
  end
  return result
end

return M
