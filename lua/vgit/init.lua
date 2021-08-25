local utils = require('vgit.utils')
local diff = require('vgit.diff')
local Hunk = require('vgit.Hunk')
local git = require('vgit.git')
local renderer = require('vgit.renderer')
local fs = require('vgit.fs')
local highlight = require('vgit.highlight')
local events = require('vgit.events')
local sign = require('vgit.sign')
local Interface = require('vgit.Interface')
local BufferCache = require('vgit.BufferCache')
local buffer = require('vgit.buffer')
local throttle_leading = require('vgit.defer').throttle_leading
local debounce_trailing = require('vgit.defer').debounce_trailing
local logger = require('vgit.logger')
local navigation = require('vgit.navigation')
local Patch = require('vgit.Patch')
local t = require('vgit.localization').translate
local wrap = require('plenary.async.async').wrap
local void = require('plenary.async.async').void
local scheduler = require('plenary.async.util').scheduler

local M = {}

local buffer_cache = BufferCache:new()

local state = Interface:new({
    config = {},
    disabled = false,
    instantiated = false,
    hunks_enabled = true,
    blames_enabled = true,
    diff_strategy = 'index',
    diff_preference = 'horizontal',
    predict_hunk_signs = true,
    action_delay_ms = 300,
    predict_hunk_throttle_ms = 300,
    predict_hunk_max_lines = 50000,
    blame_line_throttle_ms = 150,
    show_untracked_file_signs = true,
})

local function cache_buf(buf, filename, tracked_filename, tracked_remote_filename)
    buffer_cache:add(buf)
    local filetype = fs.filetype(buf)
    if not filetype or filetype == '' then
        filetype = fs.detect_filetype(filename)
    end
    buffer_cache:set(buf, 'filetype', filetype)
    buffer_cache:set(buf, 'filename', filename)
    if tracked_filename and tracked_filename ~= '' then
        buffer_cache:set(buf, 'tracked_filename', tracked_filename)
        buffer_cache:set(buf, 'tracked_remote_filename', tracked_remote_filename)
    else
        buffer_cache:set(buf, 'untracked', true)
    end
end

local function attach_blames_autocmd(buf)
    events.buf.on(
        buf,
        'CursorHold',
        string.format(':lua require("vgit")._blame_line(%s)', buf),
        { key = string.format('%s/CursorHold', buf) }
    )
    events.buf.on(
        buf,
        'CursorMoved',
        string.format(':lua require("vgit")._unblame_line(%s)', buf),
        { key = string.format('%s/CursorMoved', buf) }
    )
end

local function detach_blames_autocmd(buf)
    events.off(string.format('%s/CursorHold', buf))
    events.off(string.format('%s/CursorMoved', buf))
end

local function get_hunk_calculator()
    return (state:get('diff_strategy') == 'remote' and git.remote_hunks) or git.index_hunks
end

local function calculate_hunks(buf)
    return get_hunk_calculator()(buffer_cache:get(buf, 'tracked_filename'))
end

local function get_current_hunk(hunks, lnum)
    for i = 1, #hunks do
        local hunk = hunks[i]
        if lnum == 1 and hunk.start == 0 and hunk.finish == 0 then
            return hunk
        end
        if lnum >= hunk.start and lnum <= hunk.finish then
            return hunk
        end
    end
end

local ext_hunk_generation = void(function(buf, original_lines, current_lines)
    scheduler()
    if state:get('disabled') or not buffer.is_valid(buf) or not buffer_cache:contains(buf) then
        return
    end
    local temp_filename_b = fs.tmpname()
    local temp_filename_a = fs.tmpname()
    fs.write_file(temp_filename_a, original_lines)
    scheduler()
    fs.write_file(temp_filename_b, current_lines)
    scheduler()
    local hunks_err, hunks = git.file_hunks(temp_filename_a, temp_filename_b)
    scheduler()
    if not hunks_err then
        if not buffer_cache:contains(buf) then
            fs.remove_file(temp_filename_a)
            scheduler()
            fs.remove_file(temp_filename_b)
            scheduler()
            return
        end
        buffer_cache:set(buf, 'hunks', hunks)
        renderer.hide_hunk_signs(buf)
        renderer.render_hunk_signs(buf, hunks)
    else
        logger.debug(hunks_err, 'init.lua/ext_hunk_generation')
    end
    fs.remove_file(temp_filename_a)
    scheduler()
    fs.remove_file(temp_filename_b)
    scheduler()
end)

local generate_tracked_hunk_signs = debounce_trailing(
    void(function(buf)
        scheduler()
        if state:get('disabled') or not buffer.is_valid(buf) or not buffer_cache:contains(buf) then
            return
        end
        local max_lines_limit = state:get('predict_hunk_max_lines')
        if vim.api.nvim_buf_line_count(buf) > max_lines_limit then
            return
        end
        local tracked_filename = buffer_cache:get(buf, 'tracked_filename')
        local tracked_remote_filename = buffer_cache:get(buf, 'tracked_remote_filename')
        local show_err, original_lines
        if state:get('diff_strategy') == 'remote' then
            show_err, original_lines = git.show(tracked_remote_filename, M.get_diff_base())
        else
            show_err, original_lines = git.show(tracked_remote_filename, '')
        end
        scheduler()
        if show_err then
            local err = show_err[1]
            if vim.startswith(err, string.format('fatal: path \'%s\' exists on disk', tracked_filename)) then
                original_lines = {}
                show_err = nil
            end
        end
        if not show_err then
            if not buffer_cache:contains(buf) then
                return
            end
            local current_lines = buffer.get_lines(buf)
            if not buffer_cache:contains(buf) then
                return
            end
            buffer_cache:set(buf, 'temp_lines', current_lines)
            ext_hunk_generation(buf, original_lines, current_lines)
        else
            logger.debug(show_err, 'init.lua/generate_tracked_hunk_signs')
        end
    end),
    state:get('predict_hunk_throttle_ms')
)

local generate_untracked_hunk_signs = debounce_trailing(
    void(function(buf)
        scheduler()
        if state:get('disabled') or not buffer.is_valid(buf) or not buffer_cache:contains(buf) then
            return
        end
        local hunks = git.untracked_hunks(buffer.get_lines(buf))
        scheduler()
        if not buffer_cache:contains(buf) then
            return
        end
        buffer_cache:set(buf, 'hunks', hunks)
        renderer.hide_hunk_signs(buf)
        renderer.render_hunk_signs(buf, hunks)
    end),
    state:get('predict_hunk_throttle_ms')
)

local buf_attach_tracked = void(function(buf)
    scheduler()
    if state:get('disabled') or not buffer.is_valid(buf) or not buffer_cache:contains(buf) then
        return
    end
    if state:get('blames_enabled') then
        attach_blames_autocmd(buf)
    end
    vim.api.nvim_buf_attach(buf, false, {
        on_lines = void(function(_, cbuf, _, _, p_lnum, n_lnum, byte_count)
            scheduler()
            if
                not state:get('predict_hunk_signs')
                or (p_lnum == n_lnum and byte_count == 0)
                or not state:get('hunks_enabled')
                or not buffer_cache:contains(buf)
            then
                return
            end
            generate_tracked_hunk_signs(cbuf)
        end),
        on_detach = function(_, cbuf)
            if buffer_cache:contains(cbuf) then
                buffer_cache:remove(cbuf)
                detach_blames_autocmd(cbuf)
            end
        end,
    })
    if state:get('hunks_enabled') then
        local err, hunks = calculate_hunks(buf)
        scheduler()
        if not err then
            if not buffer_cache:contains(buf) then
                return
            end
            buffer_cache:set(buf, 'hunks', hunks)
            renderer.render_hunk_signs(buf, hunks)
        else
            logger.debug(err, 'init.lua/buf_attach_tracked')
        end
    end
end)

local function buf_attach_untracked(buf)
    if state:get('disabled') or not buffer.is_valid(buf) or not buffer_cache:contains(buf) then
        return
    end
    vim.api.nvim_buf_attach(buf, false, {
        on_lines = void(function(_, cbuf, _, _, p_lnum, n_lnum, byte_count)
            scheduler()
            if
                not state:get('predict_hunk_signs')
                or (p_lnum == n_lnum and byte_count == 0)
                or not state:get('hunks_enabled')
                or not buffer_cache:contains(cbuf)
            then
                return
            end
            if not buffer_cache:get(cbuf, 'untracked') then
                return generate_tracked_hunk_signs(cbuf)
            end
            generate_untracked_hunk_signs(cbuf)
        end),
        on_detach = function(_, cbuf)
            if buffer_cache:contains(cbuf) then
                buffer_cache:remove(cbuf)
            end
        end,
    })
    if state:get('hunks_enabled') then
        local hunks = git.untracked_hunks(buffer.get_lines(buf))
        scheduler()
        if not buffer_cache:contains(buf) then
            return
        end
        buffer_cache:set(buf, 'hunks', hunks)
        renderer.render_hunk_signs(buf, hunks)
    end
end

M._buf_attach = void(function(buf)
    scheduler()
    buf = buf or buffer.current()
    if not buffer.is_valid(buf) then
        return
    end
    local filename = fs.filename(buf)
    if not filename or filename == '' or not fs.exists(filename) then
        return
    end
    local is_inside_work_tree = git.is_inside_work_tree()
    scheduler()
    if not is_inside_work_tree then
        state:set('disabled', true)
        return
    end
    if state:get('disabled') == true then
        state:set('disabled', false)
    end
    local tracked_filename = git.tracked_filename(filename)
    scheduler()
    local tracked_remote_filename = git.tracked_remote_filename(filename)
    scheduler()
    if tracked_filename and tracked_filename ~= '' then
        cache_buf(buf, filename, tracked_filename, tracked_remote_filename)
        return buf_attach_tracked(buf)
    end
    if state:get('diff_strategy') == 'index' and state:get('show_untracked_file_signs') then
        local is_ignored = git.check_ignored(filename)
        scheduler()
        if not is_ignored then
            cache_buf(buf, filename, tracked_filename, tracked_remote_filename)
            buf_attach_untracked(buf)
        end
    end
end)

M._buf_update = void(function(buf)
    scheduler()
    buf = buf or buffer.current()
    if buffer.is_valid(buf) and buffer_cache:contains(buf) then
        buffer_cache:set(buf, 'temp_lines', {})
        if state:get('hunks_enabled') then
            if
                buffer_cache:get(buf, 'untracked')
                and state:get('diff_strategy') == 'index'
                and state:get('show_untracked_file_signs')
            then
                local hunks = git.untracked_hunks(buffer.get_lines(buf))
                scheduler()
                buffer_cache:set(buf, 'hunks', hunks)
                renderer.hide_hunk_signs(buf)
                renderer.render_hunk_signs(buf, hunks)
                return
            end
            local err, hunks = calculate_hunks(buf)
            scheduler()
            if not err then
                buffer_cache:set(buf, 'hunks', hunks)
                renderer.hide_hunk_signs(buf)
                renderer.render_hunk_signs(buf, hunks)
            else
                logger.debug(err, 'init.lua/_buf_update')
            end
        end
    end
end)

M._blame_line = debounce_trailing(
    void(function(buf)
        scheduler()
        if
            not state:get('disabled')
            and buffer.is_valid(buf)
            and buffer_cache:contains(buf)
            and not buffer_cache:get(buf, 'untracked')
        then
            if not vim.api.nvim_buf_get_option(buf, 'modified') then
                local win = vim.api.nvim_get_current_win()
                local last_lnum_blamed = buffer_cache:get(buf, 'last_lnum_blamed')
                local lnum = vim.api.nvim_win_get_cursor(win)[1]
                if last_lnum_blamed ~= lnum then
                    local err, blame = git.blame_line(buffer_cache:get(buf, 'tracked_filename'), lnum)
                    scheduler()
                    if not err then
                        renderer.hide_blame_line(buf)
                        scheduler()
                        if vim.api.nvim_win_get_cursor(vim.api.nvim_get_current_win())[1] == lnum then
                            renderer.render_blame_line(buf, blame, lnum, git.state:get('config'))
                            scheduler()
                            buffer_cache:set(buf, 'last_lnum_blamed', lnum)
                        end
                    else
                        logger.debug(err, 'init.lua/_blame_line')
                    end
                end
            end
        end
        scheduler()
    end),
    state:get('blame_line_throttle_ms')
)

M._unblame_line = function(buf, override)
    if buffer_cache:contains(buf) and buffer.is_valid(buf) and not buffer_cache:get(buf, 'untracked') then
        if override then
            return renderer.hide_blame_line(buf)
        end
        local win = vim.api.nvim_get_current_win()
        local lnum = vim.api.nvim_win_get_cursor(win)[1]
        local last_lnum_blamed = buffer_cache:get(buf, 'last_lnum_blamed')
        if lnum ~= last_lnum_blamed then
            renderer.hide_blame_line(buf)
        end
    end
end

M._run_command = function(command, ...)
    if not state:get('disabled') then
        local starts_with = command:sub(1, 1)
        if starts_with == '_' or not M[command] or not type(M[command]) == 'function' then
            logger.error(t('errors/invalid_command', command))
            return
        end
        return M[command](...)
    end
end

M._command_autocompletes = function(arglead, line)
    local parsed_line = #vim.split(line, '%s+')
    local matches = {}
    if parsed_line == 2 then
        for func, _ in pairs(M) do
            if not vim.startswith(func, '_') and vim.startswith(func, arglead) then
                matches[#matches + 1] = func
            end
        end
    end
    return matches
end

M._rerender_history = throttle_leading(
    void(function(buf)
        scheduler()
        if
            not state:get('disabled')
            and buffer.is_valid(buf)
            and buffer_cache:contains(buf)
            and not buffer_cache:get(buf, 'untracked')
        then
            local selected_log = vim.api.nvim_win_get_cursor(0)[1]
            if selected_log == 1 then
                return
            else
                selected_log = selected_log - 1
            end
            local diff_preference = state:get('diff_preference')
            local calculate_diff = (diff_preference == 'horizontal' and diff.horizontal) or diff.vertical
            renderer.rerender_history_preview(
                wrap(function()
                    local tracked_filename = buffer_cache:get(buf, 'tracked_filename')
                    local logs = buffer_cache:get(buf, 'logs')
                    local log = logs[selected_log]
                    local err, hunks, lines, commit_hash, computed_hunks
                    if log then
                        if selected_log == 1 then
                            local temp_lines = buffer_cache:get(buf, 'temp_lines')
                            if #temp_lines ~= 0 then
                                lines = temp_lines
                                computed_hunks = buffer_cache:get(buf, 'hunks')
                            else
                                err, computed_hunks = git.remote_hunks(tracked_filename, 'HEAD')
                            end
                        else
                            err, computed_hunks = git.remote_hunks(tracked_filename, log.parent_hash, log.commit_hash)
                        end
                        scheduler()
                        if err then
                            logger.debug(err, 'init.lua/_rerender_history')
                            return err, nil
                        end
                        hunks = computed_hunks
                        commit_hash = log.commit_hash
                    else
                        return { 'Failed to access logs' }, nil
                    end
                    if commit_hash and not lines then
                        err, lines = git.show(buffer_cache:get(buf, 'tracked_remote_filename'), commit_hash)
                        scheduler()
                    elseif not lines then
                        err, lines = fs.read_file(tracked_filename)
                        scheduler()
                    end
                    if err then
                        logger.debug(err, 'init.lua/_rerender_history')
                        return err, nil
                    end
                    local diff_err, data = calculate_diff(lines, hunks)
                    scheduler()
                    if not diff_err then
                        return nil,
                            utils.readonly({
                                logs = logs,
                                diff_change = data,
                            })
                    else
                        logger.debug(diff_err, 'init.lua/_rerender_history')
                        return diff_err, nil
                    end
                end, 0),
                selected_log
            )
        end
        scheduler()
    end),
    state:get('action_delay_ms')
)

M._rerender_project_diff = throttle_leading(
    void(function()
        local selected_file = vim.api.nvim_win_get_cursor(0)[1]
        if selected_file == 1 then
            return
        else
            selected_file = selected_file - 1
        end
        if not state:get('disabled') then
            local diff_preference = state:get('diff_preference')
            local calculate_diff = (diff_preference == 'horizontal' and diff.horizontal) or diff.vertical
            renderer.rerender_project_diff_preview(
                wrap(function()
                    local changed_files_err, changed_files = git.ls_changed()
                    scheduler()
                    if not changed_files_err then
                        local file = changed_files[selected_file]
                        if not file then
                            return { 'File not found' },
                                utils.readonly({
                                    changed_files = changed_files,
                                })
                        end
                        local filename = file.filename
                        local hunk_calculator = get_hunk_calculator()
                        local hunks_err, hunks = hunk_calculator(filename)
                        if not hunks_err then
                            local files_err, lines = fs.read_file(filename)
                            if not files_err then
                                local diff_err, data = calculate_diff(lines, hunks)
                                scheduler()
                                if not diff_err then
                                    return diff_err,
                                        utils.readonly({
                                            changed_files = changed_files,
                                            diff_change = data,
                                            filetype = fs.detect_filetype(filename),
                                        })
                                else
                                    logger.debug(diff_err, 'init.lua/buffer_history')
                                    return diff_err, nil
                                end
                            else
                                logger.debug(files_err, 'init.lua/diff')
                                return files_err,
                                    utils.readonly({
                                        changed_files = changed_files,
                                    })
                            end
                        else
                            logger.debug(hunks_err, 'init.lua/diff')
                            return hunks_err, nil
                        end
                    else
                        logger.debug(changed_files_err, 'init.lua/diff')
                        return changed_files_err, nil
                    end
                end, 0),
                selected_file
            )
        end
    end),
    state:get('action_delay_ms')
)

M._keep_popup_focused = function()
    local preview = renderer.get_rendered_popup()
    if not vim.tbl_isempty(preview) and preview:is_mounted() then
        local win_ids = preview:get_win_ids()
        if #win_ids > 1 then
            local current_win_id = vim.api.nvim_get_current_win()
            if not vim.tbl_contains(win_ids, current_win_id) then
                local next_win_id = preview:get_next_win_id()
                vim.api.nvim_set_current_win(next_win_id)
            else
                preview:regenerate_win_toggle_queue()
            end
        end
    end
end

M.buffer_hunk_preview = throttle_leading(function(buf, win)
    buf = buf or buffer.current()
    if
        not state:get('disabled')
        and buffer.is_valid(buf)
        and buffer_cache:contains(buf)
        and not buffer_cache:get(buf, 'untracked')
    then
        local lnum = vim.api.nvim_win_get_cursor(win)[1]
        local hunks = buffer_cache:get(buf, 'hunks')
        renderer.render_hunk_preview(
            wrap(function()
                local read_file_err, lines = fs.read_file(buffer_cache:get(buf, 'tracked_filename'))
                scheduler()
                if read_file_err then
                    logger.debug(read_file_err, 'init.lua/buffer_hunk_lens')
                    return read_file_err, nil
                end
                local diff_err, data = diff.horizontal(lines, hunks)
                scheduler()
                return diff_err,
                    {
                        diff_change = data,
                        selected_hunk = get_current_hunk(hunks, lnum) or Hunk:new(),
                    }
            end, 0),
            buffer_cache:get(buf, 'filetype')
        )
    end
end, state:get(
    'action_delay_ms'
))

M.buffer_gutter_blame_preview = throttle_leading(function(buf)
    buf = buf or buffer.current()
    if
        not state:get('disabled')
        and buffer.is_valid(buf)
        and buffer_cache:contains(buf)
        and not buffer_cache:get(buf, 'untracked')
    then
        renderer.render_gutter_blame_preview(
            wrap(function()
                local filename = buffer_cache:get(buf, 'tracked_filename')
                local read_file_err, lines = fs.read_file(filename)
                scheduler()
                if read_file_err then
                    logger.debug(read_file_err, 'init.lua/buffer_gutter_blame_preview')
                    return read_file_err, nil
                end
                local blames_err, blames = git.blames(filename)
                scheduler()
                if blames_err then
                    logger.debug(blames_err, 'init.lua/buffer_gutter_blame_preview')
                    return blames_err, nil
                end
                local hunk_calculator = get_hunk_calculator()
                local hunks_err, hunks = hunk_calculator(filename)
                scheduler()
                if hunks_err then
                    logger.debug(hunks_err, 'init.lua/buffer_gutter_blame_preview')
                    return hunks_err, nil
                end
                return nil,
                    {
                        blames = blames,
                        lines = lines,
                        hunks = hunks,
                    }
            end, 0),
            buffer_cache:get(buf, 'filetype')
        )
    end
end, state:get(
    'action_delay_ms'
))

M.hunk_down = function(buf, win)
    buf = buf or buffer.current()
    if not state:get('disabled') then
        local popup = renderer.get_rendered_popup()
        if not vim.tbl_isempty(popup) then
            if renderer.is_popup_navigatable(popup) then
                local marks = popup:get_marks()
                if popup:is_preview_focused() and #marks ~= 0 then
                    return navigation.mark_down(popup:get_preview_win_ids(), marks)
                end
            end
        end
        if buffer.is_valid(buf) and buffer_cache:contains(buf) then
            win = win or vim.api.nvim_get_current_win()
            local hunks = buffer_cache:get(buf, 'hunks')
            if #hunks ~= 0 then
                navigation.hunk_down({ win }, hunks)
            end
        end
    end
end

M.hunk_up = function(buf, win)
    buf = buf or buffer.current()
    if not state:get('disabled') then
        local popup = renderer.get_rendered_popup()
        if not vim.tbl_isempty(popup) then
            if renderer.is_popup_navigatable(popup) then
                local marks = popup:get_marks()
                if popup:is_preview_focused() and #marks ~= 0 then
                    return navigation.mark_up(popup:get_preview_win_ids(), marks)
                end
            end
        end
        if buffer.is_valid(buf) and buffer_cache:contains(buf) then
            win = win or vim.api.nvim_get_current_win()
            local hunks = buffer_cache:get(buf, 'hunks')
            if #hunks ~= 0 then
                navigation.hunk_up({ win }, hunks)
            end
        end
    end
end

M.buffer_hunk_reset = throttle_leading(function(buf, win)
    buf = buf or buffer.current()
    if
        not state:get('disabled')
        and buffer.is_valid(buf)
        and buffer_cache:contains(buf)
        and not buffer_cache:get(buf, 'untracked')
    then
        win = win or vim.api.nvim_get_current_win()
        local hunks = buffer_cache:get(buf, 'hunks')
        local lnum = vim.api.nvim_win_get_cursor(win)[1]
        if lnum == 1 then
            local current_lines = buffer.get_lines(buf)
            if #hunks > 0 and #current_lines == 1 and current_lines[1] == '' then
                local all_removes = true
                for i = 1, #hunks do
                    local hunk = hunks[i]
                    if hunk.type ~= 'remove' then
                        all_removes = false
                        break
                    end
                end
                if all_removes then
                    return M.buffer_reset(buf)
                end
            end
        end
        local selected_hunk = nil
        local selected_hunk_index = nil
        for i = 1, #hunks do
            local hunk = hunks[i]
            if
                (lnum >= hunk.start and lnum <= hunk.finish)
                or (hunk.start == 0 and hunk.finish == 0 and lnum - 1 == hunk.start and lnum - 1 == hunk.finish)
            then
                selected_hunk = hunk
                selected_hunk_index = i
                break
            end
        end
        if selected_hunk then
            local replaced_lines = {}
            for i = 1, #selected_hunk.diff do
                local line = selected_hunk.diff[i]
                local is_line_removed = vim.startswith(line, '-')
                if is_line_removed then
                    replaced_lines[#replaced_lines + 1] = string.sub(line, 2, -1)
                end
            end
            local start = selected_hunk.start
            local finish = selected_hunk.finish
            if start and finish then
                if selected_hunk.type == 'remove' then
                    vim.api.nvim_buf_set_lines(buf, start, finish, false, replaced_lines)
                else
                    vim.api.nvim_buf_set_lines(buf, start - 1, finish, false, replaced_lines)
                end
                local new_lnum = start
                if new_lnum < 1 then
                    new_lnum = 1
                end
                navigation.set_cursor(win, { new_lnum, 0 })
                vim.cmd('update')
                table.remove(hunks, selected_hunk_index)
                renderer.hide_hunk_signs(buf)
                renderer.render_hunk_signs(buf, hunks)
            end
        end
    end
end, state:get(
    'action_delay_ms'
))

M.project_hunks_qf = throttle_leading(
    void(function()
        scheduler()
        if not state:get('disabled') then
            local qf_entries = {}
            local err, filenames = git.ls_changed()
            scheduler()
            if err then
                return logger.debug(err, 'init.lua/hunks_quickfix_list')
            end
            for i = 1, #filenames do
                local filename = filenames[i].filename
                local hunk_calculator = get_hunk_calculator()
                local hunks_err, hunks = hunk_calculator(filename)
                scheduler()
                if not hunks_err then
                    for j = 1, #hunks do
                        local hunk = hunks[j]
                        qf_entries[#qf_entries + 1] = {
                            text = string.format('[%s..%s]', hunk.start, hunk.finish),
                            filename = filename,
                            lnum = hunk.start,
                            col = 0,
                        }
                    end
                else
                    logger.debug(hunks_err, 'init.lua/hunks_quickfix_list')
                end
            end
            if #qf_entries ~= 0 then
                vim.fn.setqflist(qf_entries, 'r')
                vim.cmd('copen')
            end
        end
    end),
    state:get('action_delay_ms')
)

M.project_diff = throttle_leading(
    void(function()
        if not state:get('disabled') then
            local diff_preference = state:get('diff_preference')
            local calculate_diff = (diff_preference == 'horizontal' and diff.horizontal) or diff.vertical
            local changed_files_err, changed_files = git.ls_changed()
            scheduler()
            if changed_files_err then
                return logger.debug(changed_files_err, 'init.lua/diff')
            end
            if #changed_files == 0 then
                return
            end
            renderer.render_project_diff_preview(
                wrap(function()
                    local selected_file = 1
                    local file = changed_files[selected_file]
                    if not file then
                        return { 'File not found' },
                            utils.readonly({
                                changed_files = changed_files,
                            })
                    end
                    local filename = file.filename
                    local hunk_calculator = get_hunk_calculator()
                    local hunks_err, hunks = hunk_calculator(filename)
                    if not hunks_err then
                        local files_err, lines = fs.read_file(filename)
                        if not files_err then
                            local diff_err, data = calculate_diff(lines, hunks)
                            scheduler()
                            if not diff_err then
                                return diff_err,
                                    utils.readonly({
                                        changed_files = changed_files,
                                        diff_change = data,
                                        filetype = fs.detect_filetype(filename),
                                    })
                            else
                                logger.debug(diff_err, 'init.lua/buffer_history')
                                return diff_err, nil
                            end
                        else
                            logger.debug(files_err, 'init.lua/diff')
                            return files_err,
                                utils.readonly({
                                    changed_files = changed_files,
                                })
                        end
                    else
                        logger.debug(hunks_err, 'init.lua/diff')
                        return hunks_err, nil
                    end
                end, 0),
                diff_preference
            )
        end
    end),
    state:get('action_delay_ms')
)

M.toggle_buffer_hunks = throttle_leading(
    void(function()
        scheduler()
        if not state:get('disabled') then
            if state:get('hunks_enabled') then
                state:set('hunks_enabled', false)
                buffer_cache:for_each(function(buf, buf_state)
                    if buffer.is_valid(buf) then
                        buf_state:set('hunks', {})
                        renderer.hide_hunk_signs(buf)
                    end
                end)
                return state:get('hunks_enabled')
            else
                state:set('hunks_enabled', true)
            end
            buffer_cache:for_each(function(buf, buf_state)
                if buffer.is_valid(buf) then
                    local hunks_err, hunks = calculate_hunks(buf)
                    scheduler()
                    if not hunks_err then
                        state:set('hunks_enabled', true)
                        buf_state:set('hunks', hunks)
                        renderer.hide_hunk_signs(buf)
                        renderer.render_hunk_signs(buf, hunks)
                    else
                        logger.debug(hunks_err, 'init.lua/toggle_buffer_hunks')
                    end
                end
            end)
        end
        return state:get('hunks_enabled')
    end),
    state:get('action_delay_ms')
)

M.toggle_buffer_blames = throttle_leading(
    void(function()
        scheduler()
        if not state:get('disabled') then
            if state:get('blames_enabled') then
                state:set('blames_enabled', false)
                buffer_cache:for_each(function(buf, buf_state)
                    if buffer.is_valid(buf) then
                        detach_blames_autocmd(buf)
                        buf_state:set('blames', {})
                        M._unblame_line(buf, true)
                    end
                end)
                return state:get('blames_enabled')
            else
                state:set('blames_enabled', true)
            end
            buffer_cache:for_each(function(buf)
                if buffer.is_valid(buf) then
                    attach_blames_autocmd(buf)
                end
            end)
            return state:get('blames_enabled')
        end
    end),
    state:get('action_delay_ms')
)

M.buffer_history_preview = throttle_leading(
    void(function(buf)
        buf = buf or buffer.current()
        if
            not state:get('disabled')
            and buffer.is_valid(buf)
            and buffer_cache:contains(buf)
            and not buffer_cache:get(buf, 'untracked')
        then
            local diff_preference = state:get('diff_preference')
            local calculate_diff = (diff_preference == 'horizontal' and diff.horizontal) or diff.vertical
            renderer.render_history_preview(
                wrap(function()
                    local tracked_filename = buffer_cache:get(buf, 'tracked_filename')
                    local logs_err, logs = git.logs(tracked_filename)
                    scheduler()
                    if not logs_err then
                        buffer_cache:set(buf, 'logs', logs)
                        local temp_lines = buffer_cache:get(buf, 'temp_lines')
                        if #temp_lines ~= 0 then
                            local lines = temp_lines
                            local hunks = buffer_cache:get(buf, 'hunks')
                            local diff_err, data = calculate_diff(lines, hunks)
                            scheduler()
                            if not diff_err then
                                return diff_err,
                                    utils.readonly({
                                        logs = logs,
                                        diff_change = data,
                                    })
                            else
                                logger.debug(diff_err, 'init.lua/buffer_history')
                                return diff_err, nil
                            end
                        else
                            local read_file_err, lines = fs.read_file(tracked_filename)
                            scheduler()
                            if not read_file_err then
                                local hunks_err, hunks = git.remote_hunks(tracked_filename, 'HEAD')
                                scheduler()
                                if hunks_err then
                                    logger.debug(hunks_err, 'init.lua/buffer_history')
                                    return hunks_err, nil
                                end
                                local diff_err, data = calculate_diff(lines, hunks)
                                scheduler()
                                if not diff_err then
                                    return diff_err,
                                        utils.readonly({
                                            logs = logs,
                                            diff_change = data,
                                        })
                                else
                                    logger.debug(diff_err, 'init.lua/buffer_history')
                                    return diff_err, nil
                                end
                            else
                                logger.debug(read_file_err, 'init.lua/buffer_history')
                                return read_file_err, nil
                            end
                        end
                    else
                        logger.debug(logs_err, 'init.lua/buffer_history')
                        return logs_err, nil
                    end
                end, 0),
                buffer_cache:get(buf, 'filetype'),
                diff_preference
            )
        end
    end),
    state:get('action_delay_ms')
)

M.buffer_diff_preview = throttle_leading(
    void(function(buf)
        buf = buf or buffer.current()
        if
            not state:get('disabled')
            and buffer.is_valid(buf)
            and buffer_cache:contains(buf)
            and not buffer_cache:get(buf, 'untracked')
        then
            local diff_preference = state:get('diff_preference')
            local calculate_diff = (diff_preference == 'horizontal' and diff.horizontal) or diff.vertical
            renderer.render_diff_preview(
                wrap(function()
                    local tracked_filename = buffer_cache:get(buf, 'tracked_filename')
                    local hunks
                    if state:get('hunks_enabled') then
                        hunks = buffer_cache:get(buf, 'hunks')
                    else
                        local hunks_err, computed_hunks = calculate_hunks(buf)
                        scheduler()
                        if hunks_err then
                            logger.debug(hunks_err, 'init.lua/buffer_preview')
                            return hunks_err, nil
                        else
                            hunks = computed_hunks
                        end
                    end
                    if not hunks then
                        return { 'Failed to retrieve hunks for the current buffer' }, nil
                    end
                    local temp_lines = buffer_cache:get(buf, 'temp_lines')
                    local read_file_err, lines
                    if #temp_lines ~= 0 then
                        lines = temp_lines
                    else
                        read_file_err, lines = fs.read_file(tracked_filename)
                        scheduler()
                        if read_file_err then
                            logger.debug(read_file_err, 'init.lua/buffer_preview')
                            return read_file_err, nil
                        end
                    end
                    local diff_err, data = calculate_diff(lines, hunks)
                    scheduler()
                    return diff_err, data
                end, 0),
                buffer_cache:get(buf, 'filetype'),
                diff_preference
            )
        end
    end),
    state:get('action_delay_ms')
)

M.buffer_staged_diff_preview = throttle_leading(
    void(function(buf)
        buf = buf or buffer.current()
        if
            not state:get('disabled')
            and buffer.is_valid(buf)
            and buffer_cache:contains(buf)
            and not buffer_cache:get(buf, 'untracked')
            and state:get('diff_strategy') == 'index'
        then
            local diff_preference = state:get('diff_preference')
            local calculate_diff = (diff_preference == 'horizontal' and diff.horizontal) or diff.vertical
            renderer.render_diff_preview(
                wrap(function()
                    local tracked_filename = buffer_cache:get(buf, 'tracked_filename')
                    local hunks_err, hunks = git.staged_hunks(tracked_filename)
                    scheduler()
                    if hunks_err then
                        logger.debug(hunks_err, 'init.lua/staged_buffer_preview')
                        return hunks_err, nil
                    end
                    scheduler()
                    local show_err, lines = git.show(buffer_cache:get(buf, 'tracked_remote_filename'))
                    scheduler()
                    if show_err then
                        logger.debug(show_err, 'init.lua/staged_buffer_preview')
                        return show_err, nil
                    end
                    local diff_err, data = calculate_diff(lines, hunks)
                    scheduler()
                    return diff_err, data
                end, 0),
                buffer_cache:get(buf, 'filetype'),
                diff_preference
            )
        end
    end),
    state:get('action_delay_ms')
)

M.buffer_reset = throttle_leading(
    void(function(buf)
        scheduler()
        buf = buf or buffer.current()
        if
            not state:get('disabled')
            and buffer.is_valid(buf)
            and buffer_cache:contains(buf)
            and not buffer_cache:get(buf, 'untracked')
        then
            local hunks = buffer_cache:get(buf, 'hunks')
            if #hunks ~= 0 then
                local tracked_remote_filename = buffer_cache:get(buf, 'tracked_remote_filename')
                if state:get('diff_strategy') == 'remote' then
                    local err, lines = git.show(tracked_remote_filename, 'HEAD')
                    scheduler()
                    if not err then
                        buffer.set_lines(buf, lines)
                        vim.cmd('update')
                    else
                        logger.debug(err, 'init.lua/buffer_reset')
                    end
                else
                    local err, lines = git.show(tracked_remote_filename, '')
                    scheduler()
                    if not err then
                        buffer.set_lines(buf, lines)
                        vim.cmd('update')
                    else
                        logger.debug(err, 'init.lua/buffer_reset')
                    end
                end
            end
        end
    end),
    state:get('action_delay_ms')
)

M.buffer_show_blame = throttle_leading(
    void(function(buf)
        scheduler()
        buf = buf or buffer.current()
        if
            not state:get('disabled')
            and buffer.is_valid(buf)
            and buffer_cache:contains(buf)
            and not buffer_cache:get(buf, 'untracked')
        then
            local has_commits = git.has_commits()
            scheduler()
            if has_commits then
                local win = vim.api.nvim_get_current_win()
                local lnum = vim.api.nvim_win_get_cursor(win)[1]
                renderer.render_blame_preview(wrap(function()
                    local err, blame = git.blame_line(buffer_cache:get(buf, 'tracked_filename'), lnum)
                    scheduler()
                    return err, blame
                end, 0))
            end
        end
    end),
    state:get('action_delay_ms')
)

M.buffer_hunk_stage = throttle_leading(
    void(function(buf, win)
        scheduler()
        buf = buf or buffer.current()
        if
            not state:get('disabled')
            and buffer.is_valid(buf)
            and buffer_cache:contains(buf)
            and not vim.api.nvim_buf_get_option(buf, 'modified')
            and state:get('diff_strategy') == 'index'
        then
            -- If buffer is untracked then, the whole file is the hunk.
            if buffer_cache:get(buf, 'untracked') then
                local filename = buffer_cache:get(buf, 'filename')
                local err = git.stage_file(filename)
                scheduler()
                if not err then
                    local tracked_filename = git.tracked_filename(filename)
                    scheduler()
                    local tracked_remote_filename = git.tracked_remote_filename(filename)
                    scheduler()
                    buffer_cache:set(buf, 'tracked_filename', tracked_filename)
                    buffer_cache:set(buf, 'tracked_remote_filename', tracked_remote_filename)
                    buffer_cache:set(buf, 'hunks', {})
                    buffer_cache:set(buf, 'untracked', false)
                    renderer.hide_hunk_signs(buf)
                    renderer.render_hunk_signs(buf, {})
                else
                    logger.debug(err, 'init.lua/hunk_stage')
                end
                return
            end
            win = win or vim.api.nvim_get_current_win()
            local lnum = vim.api.nvim_win_get_cursor(win)[1]
            local hunks = buffer_cache:get(buf, 'hunks')
            local selected_hunk = get_current_hunk(hunks, lnum)
            if selected_hunk then
                local tracked_filename = buffer_cache:get(buf, 'tracked_filename')
                local tracked_remote_filename = buffer_cache:get(buf, 'tracked_remote_filename')
                local patch = Patch:new(tracked_remote_filename, selected_hunk)
                local patch_filename = fs.tmpname()
                fs.write_file(patch_filename, patch)
                scheduler()
                local err = git.stage_hunk_from_patch(patch_filename)
                scheduler()
                fs.remove_file(patch_filename)
                scheduler()
                if not err then
                    local hunks_err, calculated_hunks = git.index_hunks(tracked_filename)
                    scheduler()
                    if not hunks_err then
                        buffer_cache:set(buf, 'hunks', calculated_hunks)
                        renderer.hide_hunk_signs(buf)
                        renderer.render_hunk_signs(buf, calculated_hunks)
                    else
                        logger.debug(err, 'init.lua/hunk_stage')
                    end
                else
                    logger.debug(err, 'init.lua/hunk_stage')
                end
            end
        end
    end),
    state:get('action_delay_ms')
)

M.buffer_stage = throttle_leading(
    void(function(buf)
        scheduler()
        buf = buf or buffer.current()
        if
            not state:get('disabled')
            and buffer.is_valid(buf)
            and buffer_cache:contains(buf)
            and not vim.api.nvim_buf_get_option(buf, 'modified')
            and state:get('diff_strategy') == 'index'
        then
            local filename = buffer_cache:get(buf, 'filename')
            local tracked_filename = buffer_cache:get(buf, 'tracked_filename')
            local err = git.stage_file((tracked_filename and tracked_filename ~= '' and tracked_filename) or filename)
            scheduler()
            if not err then
                if buffer_cache:get(buf, 'untracked') then
                    tracked_filename = git.tracked_filename(filename)
                    scheduler()
                    local tracked_remote_filename = git.tracked_remote_filename(filename)
                    scheduler()
                    buffer_cache:set(buf, 'tracked_filename', tracked_filename)
                    buffer_cache:set(buf, 'tracked_remote_filename', tracked_remote_filename)
                    buffer_cache:set(buf, 'untracked', false)
                end
                buffer_cache:set(buf, 'hunks', {})
                renderer.hide_hunk_signs(buf)
                renderer.render_hunk_signs(buf, {})
            else
                logger.debug(err, 'init.lua/stage_buffer')
            end
        end
    end),
    state:get('action_delay_ms')
)

M.buffer_unstage = throttle_leading(
    void(function(buf)
        scheduler()
        buf = buf or buffer.current()
        if
            not state:get('disabled')
            and buffer.is_valid(buf)
            and buffer_cache:contains(buf)
            and not vim.api.nvim_buf_get_option(buf, 'modified')
            and state:get('diff_strategy') == 'index'
            and not buffer_cache:get(buf, 'untracked')
        then
            local filename = buffer_cache:get(buf, 'filename')
            local tracked_filename = buffer_cache:get(buf, 'tracked_filename')
            local err = git.unstage_file(tracked_filename)
            scheduler()
            if not err then
                tracked_filename = git.tracked_filename(filename)
                scheduler()
                local tracked_remote_filename = git.tracked_remote_filename(filename)
                scheduler()
                buffer_cache:set(buf, 'tracked_filename', tracked_filename)
                buffer_cache:set(buf, 'tracked_remote_filename', tracked_remote_filename)
                if tracked_filename and tracked_filename ~= '' then
                    buffer_cache:set(buf, 'untracked', false)
                    local hunks_err, calculated_hunks = git.index_hunks(tracked_filename)
                    scheduler()
                    if not hunks_err then
                        buffer_cache:set(buf, 'hunks', calculated_hunks)
                        renderer.hide_hunk_signs(buf)
                        renderer.render_hunk_signs(buf, calculated_hunks)
                    else
                        logger.debug(err, 'init.lua/unstage_buffer')
                    end
                else
                    buffer_cache:set(buf, 'untracked', true)
                    local hunks = git.untracked_hunks(buffer.get_lines(buf))
                    scheduler()
                    buffer_cache:set(buf, 'hunks', hunks)
                    renderer.hide_hunk_signs(buf)
                    renderer.render_hunk_signs(buf, hunks)
                end
            else
                logger.debug(err, 'init.lua/unstage_buffer')
            end
        end
    end),
    state:get('action_delay_ms')
)

M.get_diff_base = function()
    return git.get_diff_base()
end

M.get_diff_strategy = function()
    return state:get('diff_strategy')
end

M.get_diff_preference = function()
    return state:get('diff_preference')
end

M.set_diff_base = throttle_leading(
    void(function(diff_base)
        scheduler()
        if not diff_base or type(diff_base) ~= 'string' then
            logger.error(t('errors/set_diff_base', diff_base))
            return
        end
        if git.state:get('diff_base') == diff_base then
            return
        end
        local is_commit_valid = git.is_commit_valid(diff_base)
        scheduler()
        if not is_commit_valid then
            logger.error(t('errors/set_diff_base', diff_base))
        else
            git.set_diff_base(diff_base)
            if state:get('diff_strategy') == 'remote' then
                local buf_states = buffer_cache:get_buf_states()
                for buf, buf_state in pairs(buf_states) do
                    local hunks_err, hunks = git.remote_hunks(buf_state:get('tracked_filename'))
                    scheduler()
                    if not hunks_err then
                        buf_state:set('hunks', hunks)
                        renderer.hide_hunk_signs(buf)
                        renderer.render_hunk_signs(buf, hunks)
                    else
                        logger.debug(hunks_err, 'init.lua/set_diff_base')
                    end
                end
            end
        end
    end),
    state:get('action_delay_ms')
)

M.set_diff_preference = throttle_leading(
    void(function(preference)
        scheduler()
        if preference ~= 'horizontal' and preference ~= 'vertical' then
            return logger.error(t('errors/set_diff_preference', preference))
        end
        local current_preference = state:get('diff_preference')
        if current_preference == preference then
            return
        end
        state:set('diff_preference', preference)
    end),
    state:get('action_delay_ms')
)

M.set_diff_strategy = throttle_leading(
    void(function(preference)
        scheduler()
        if preference ~= 'remote' and preference ~= 'index' then
            return logger.error(t('errors/set_diff_strategy', preference))
        end
        local current_preference = state:get('diff_strategy')
        if current_preference == preference then
            return
        end
        state:set('diff_strategy', preference)
        buffer_cache:for_each(function(buf, buf_state)
            if buffer.is_valid(buf) then
                local hunks_err, hunks = calculate_hunks(buf)
                scheduler()
                if not hunks_err then
                    state:set('hunks_enabled', true)
                    buf_state:set('hunks', hunks)
                    renderer.hide_hunk_signs(buf)
                    renderer.render_hunk_signs(buf, hunks)
                else
                    logger.debug(hunks_err, 'init.lua/set_diff_strategy')
                end
            end
        end)
    end),
    state:get('action_delay_ms')
)

M.show_debug_logs = function()
    if logger.state:get('debug') then
        local debug_logs = logger.state:get('debug_logs')
        for i = 1, #debug_logs do
            local log = debug_logs[i]
            logger.error(log)
        end
    end
end

M.apply_highlights = function()
    highlight.setup(state:get('config'))
end

-- Aliases
M.hunk_stage = M.buffer_hunk_stage
M.stage_buffer = M.buffer_stage
M.unstage_buffer = M.buffer_unstage
M.show_blame = M.buffer_show_blame
M.buffer_preview = M.buffer_diff_preview
M.staged_buffer_preview = M.buffer_staged_diff_preview
M.buffer_history = M.buffer_history_preview
M.diff = M.project_diff
M.hunks_quickfix_list = M.project_hunks_qf
M.hunk_reset = M.buffer_hunk_reset
M.hunk_preview = M.buffer_hunk_preview
M.buffer_hunk_lens = M.buffer_hunk_preview

-- Submodules
M.renderer = renderer
M.events = events

M.setup = function(config)
    if state:get('instantiated') then
        logger.debug('plugin has already been instantiated', 'init.lua/setup')
        return
    else
        state:set('instantiated', true)
    end
    state:set('config', config or {})
    events.setup()
    state:assign(config)
    highlight.setup(config)
    sign.setup(config)
    logger.setup(config)
    git.setup(config)
    renderer.setup(config)
    events.on('BufWinEnter', ':lua require("vgit")._buf_attach()')
    events.on('WinEnter', ':lua require("vgit")._keep_popup_focused()')
    events.on('BufWrite', ':lua require("vgit")._buf_update()')
    vim.cmd(
        string.format(
            'com! -nargs=+ %s %s',
            '-complete=customlist,v:lua.package.loaded.vgit._command_autocompletes',
            'VGit lua require("vgit")._run_command(<f-args>)'
        )
    )
end

return M
