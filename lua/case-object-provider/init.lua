local M = {}

local function in_word()
    local cursor = vim.api.nvim_win_get_cursor(0)
    local line = vim.api.nvim_buf_get_lines(0, cursor[1] - 1, cursor[1], false)[1]

    local start_column = string.find(line:reverse(), "[^a-z0-9]", #line - cursor[2])
    if start_column == nil then
        start_column = 0
    else
        start_column = #line - start_column + 1

        if string.match(line:sub(start_column, start_column), "[A-Z]") == nil then
            start_column = start_column + 1
        end
    end

    local end_column = string.find(line, "[^a-z0-9]", cursor[2] + 2)
    if end_column == nil then
        end_column = #line
    else
        end_column = end_column - 1
    end

    return {
        first_line = cursor[1],
        start_column = start_column,
        last_line = cursor[1],
        end_column = end_column,
    }
end

local bindings = {
    {
        name = "case",
        modes = { "c" },
        key = "p",
        visual_mode = "charwise",
        callback = function(mode, requested)
            if requested == "cursor" then
                return in_word()
            elseif requested == "next" then
            elseif requested == "last" then
            elseif requested == "every" then
            end
        end,
    },
}

M.setup = function( --[[ config ]])
    for _, binding in ipairs(bindings) do
        require("unified-text-objects").register_binding(binding)
    end
end

return M
