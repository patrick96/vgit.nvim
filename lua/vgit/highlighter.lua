local configurer = require('vgit.configurer')

local vim = vim

local M = {}

local function get_initial_state()
    return {
        hls = {
            VGitBlame = {
                bg = nil,
                fg = '#b1b1b1',
            },
            VGitDiffAddSign = {
                bg = '#3d5213',
                fg = nil,
            },
            VGitDiffRemoveSign = {
                bg = '#4a0f23',
                fg = nil,
            },
            VGitDiffAddText = {
                fg = '#6a8f1f',
                bg = '#3d5213',
            },
            VGitDiffRemoveText = {
                fg = '#a3214c',
                bg = '#4a0f23',
            },
            VGitHunkAddSign = {
                bg = '#3d5213',
                fg = nil,
            },
            VGitHunkRemoveSign = {
                bg = '#4a0f23',
                fg = nil,
            },
            VGitHunkAddText = {
                fg = '#6a8f1f',
                bg = '#3d5213',
            },
            VGitHunkRemoveText = {
                fg = '#a3214c',
                bg = '#4a0f23',
            },
            VGitHunkSignAdd = {
                fg = '#d7ffaf',
                bg = '#4a6317',
            },
            VGitHunkSignRemove = {
                fg = '#e95678',
                bg = '#63132f',
            },
            VGitSignAdd = {
                fg = '#d7ffaf',
                bg = nil,
            },
            VGitSignChange = {
                fg = '#7AA6DA',
                bg = nil,
            },
            VGitSignRemove = {
                fg = '#e95678',
                bg = nil,
            },
            VGitLogsIndicator = {
                fg = '#a6e22e',
                bg = nil,
            },
            VGitDiffCurrentBorder = {
                fg = '#a1b5b1',
                bg = nil,
            },
            VGitDiffPreviousBorder = {
                fg = '#a1b5b1',
                bg = nil,
            },
            VGitLogsBorder = {
                fg = '#a1b5b1',
                bg = nil,
            },
            VGitHunkBorder = {
                fg = '#a1b5b1',
                bg = nil,
            },
        },
    }
end

M.state = get_initial_state()

M.setup = function(config)
    M.state = configurer.assign(M.state, config)
end

M.create = function(group, color)
    local gui = color.gui and 'gui = ' .. color.gui or 'gui = NONE'
    local fg = color.fg and 'guifg = ' .. color.fg or 'guifg = NONE'
    local bg = color.bg and 'guibg = ' .. color.bg or 'guibg = NONE'
    local sp = color.sp and 'guisp = ' .. color.sp or ''
    vim.api.nvim_command('highlight ' .. group .. ' ' .. gui .. ' ' .. fg .. ' ' .. bg .. ' ' .. sp)
end

M.define = function(hl)
    local color = M.state.hls[hl]
    if color then
        M.create(hl, color)
        return true
    end
    return false
end

return M