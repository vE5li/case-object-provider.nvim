local M = {}

local function in_word(include_separator)
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

    if include_separator then
        local function is_separator(character)
            return character == "_" or character == "-"
        end

        local is_first_separator = is_separator(line:sub(start_column - 1, start_column - 1))

        if is_first_separator then
            start_column = start_column - 1
        else
            local is_last_separator = is_separator(line:sub(end_column + 1, end_column + 1))

            if is_last_separator then
                end_column = end_column + 1
            end
        end
    end

    return {
        first_line = cursor[1],
        start_column = start_column,
        last_line = cursor[1],
        end_column = end_column,
    }
end

local function add_word(objects, line, line_number, start_column, end_column, include_separator)
    local word = line:sub(start_column, end_column)

    if not word:find("[a-zA-Z]") then
        -- This is just number
        return
    end

    if word:find("[_-]") then
        -- Separated by _ or -
        local word_start = start_column
        local offset = 0

        if include_separator then
            offset = 1
        end

        while start_column < end_column do
            local current_character = line:sub(start_column, start_column)

            if current_character == "_" or current_character == "-" then
                -- This check is necessary for consecutive `_` or `-`
                if word_start < start_column then
                    table.insert(objects, {
                        first_line = line_number,
                        start_column = word_start,
                        last_line = line_number,
                        end_column = start_column - 1 + offset,
                    })
                end

                -- TODO: We might want to include more that one character for the separator. That would support matches like:
                --
                -- text :  foo___bar
                -- match:  ^    ^^ ^
                --         |    |---
                --         ------
                --
                -- Currently it looks like this
                --
                -- text :  foo___bar
                -- match:  ^  ^  ^ ^
                --         ----  ---
                word_start = start_column + 1
            end

            start_column = start_column + 1
        end

        -- We need to add the last word to the objects. This will only not be hit if the last character is a '_' or '-'.
        if word_start ~= start_column then
            -- The last word is inserted differently. It uses the separator in before it rather than after it.
            -- That way, selecting around a part will always include a separator.
            table.insert(objects, {
                first_line = line_number,
                start_column = word_start - offset,
                last_line = line_number,
                end_column = start_column,
            })
        end
    elseif word:find("[A-Z][a-z]") or word:find("[a-z][A-Z]") then
        -- Separated by capital letters

        local word_end = end_column
        local waiting_for_uppercase = nil

        while end_column >= start_column do
            local current_character = line:sub(end_column, end_column)

            if waiting_for_uppercase == nil then
                waiting_for_uppercase = current_character:match("%u") == nil
            elseif waiting_for_uppercase == true then
                if current_character:match("%u") then
                    -- We got an uppercase character and want to add this character and the tail to the objects.

                    table.insert(objects, {
                        first_line = line_number,
                        start_column = end_column,
                        last_line = line_number,
                        end_column = word_end,
                    })

                    word_end = end_column - 1
                    waiting_for_uppercase = nil
                end
            elseif waiting_for_uppercase == false then
                if current_character:match("%U") then
                    -- We got a lowercase character and want to add _only_ the tail to the objects.

                    table.insert(objects, {
                        first_line = line_number,
                        start_column = end_column + 1,
                        last_line = line_number,
                        end_column = word_end,
                    })

                    word_end = end_column
                    waiting_for_uppercase = nil
                end
            end

            end_column = end_column - 1
        end

        -- We need to add the first word to the objects if it doesn't start with an uppercase letter.
        if word_end > end_column then
            table.insert(objects, {
                first_line = line_number,
                start_column = end_column + 1,
                last_line = line_number,
                end_column = word_end,
            })
        end
    end
end

local function find_all(include_separator)
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    local objects = {}

    for line_number, line in ipairs(lines) do
        local offset = 1
        local start_column, end_column = line:find("[a-zA-Z0-9_-]+", offset)

        while start_column do
            add_word(objects, line, line_number, start_column, end_column, include_separator)
            offset = end_column + 1
            start_column, end_column = line:find("[a-zA-Z0-9_-]+", offset)
        end
    end

    return objects
end

local bindings = {
    {
        name = "case",
        modes = { "i", "a" },
        key = "g",
        visual_mode = "charwise",
        callback = function(mode, requested)
            if requested == "cursor" then
                return in_word(mode == "a")
            elseif requested == "next" then
            elseif requested == "last" then
            elseif requested == "every" then
                return find_all(mode == "a")
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
