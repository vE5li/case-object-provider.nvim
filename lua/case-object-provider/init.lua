local M = {}

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
        local part_added = false

        while end_column >= start_column do
            local current_character = line:sub(end_column, end_column)

            if waiting_for_uppercase == nil then
                waiting_for_uppercase = current_character:match("%u") == nil
            elseif waiting_for_uppercase == true then
                if current_character:match("%u") then
                    -- We got an uppercase character and want to add this character and the tail to the objects.

                    -- This check filters out words such as `Test` that don't consist of multiple parts.
                    if end_column == start_column and not part_added then
                        return
                    end

                    table.insert(objects, {
                        first_line = line_number,
                        start_column = end_column,
                        last_line = line_number,
                        end_column = word_end,
                    })

                    word_end = end_column - 1
                    waiting_for_uppercase = nil
                    part_added = true
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
                    part_added = true
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

local function find_closest(include_separator)
    local cursor = vim.api.nvim_win_get_cursor(0)
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    local search_column = cursor[2] + 1
    local down_line_number = cursor[1]
    local up_line_number = cursor[1]

    while down_line_number < #lines or up_line_number > 1 do
        local down_line = lines[down_line_number]

        if down_line then
            local down_offset = 1
            local start_column, end_column = down_line:find("[a-zA-Z0-9_-]+", down_offset)
            local objects = {}

            while start_column do
                add_word(objects, down_line, down_line_number, start_column, end_column,
                    include_separator)
                down_offset = end_column + 1
                start_column, end_column = down_line:find("[a-zA-Z0-9_-]+", down_offset)
            end

            -- If we found some objects, select the best one
            if #objects > 0 then
                local best_match
                local best_distance

                for object_index, object in ipairs(objects) do
                    local distance = math.min(math.abs(object["start_column"] - (search_column or 1)),
                        math.abs(object["end_column"] - (search_column or 1)) + 1)

                    -- Best case: we have an object right under the cursor, so we instantly return that.
                    if search_column and object["start_column"] <= search_column and object["end_column"] >= search_column then
                        return object
                    elseif not best_distance or distance < best_distance then
                        best_match = object_index
                        best_distance = distance
                    end
                end

                if best_match then
                    return objects[best_match]
                end
            end
        end

        local up_line = lines[up_line_number]

        if up_line then
            local up_offset = 1
            local start_column, end_column = up_line:find("[a-zA-Z0-9_-]+", up_offset)
            local objects = {}

            while start_column do
                add_word(objects, up_line, up_line_number, start_column, end_column, include_separator)
                up_offset = end_column + 1
                start_column, end_column = up_line:find("[a-zA-Z0-9_-]+", up_offset)
            end

            -- If we found some objects, select the best one
            if #objects > 0 then
                local best_match
                local best_distance

                for object_index, object in ipairs(objects) do
                    local distance = (search_column or #up_line) - object["end_column"]

                    if (not search_column or object["end_column"] < search_column) and (not best_distance or distance < best_distance) then
                        best_match = object_index
                        best_distance = distance
                    end
                end

                if best_match then
                    return objects[best_match]
                end
            end
        end

        search_column = nil
        down_line_number = down_line_number + 1
        up_line_number = up_line_number - 1
    end
end

local function find_next(include_separator)
    local cursor = vim.api.nvim_win_get_cursor(0)
    local lines = vim.api.nvim_buf_get_lines(0, cursor[1] - 1, -1, false)
    local search_column = cursor[2] + 1

    for line_number, line in ipairs(lines) do
        local offset = 1
        local start_column, end_column = line:find("[a-zA-Z0-9_-]+", offset)
        local objects = {}

        while start_column do
            add_word(objects, line, line_number + cursor[1] - 1, start_column, end_column, include_separator)
            offset = end_column + 1
            start_column, end_column = line:find("[a-zA-Z0-9_-]+", offset)
        end

        -- If we found some objects, select the best one
        if #objects > 0 then
            local best_match
            local best_distance

            for object_index, object in ipairs(objects) do
                local distance = object["start_column"] - search_column

                if object["start_column"] > search_column and (not best_distance or distance < best_distance) then
                    best_match = object_index
                    best_distance = distance
                end
            end

            if best_match then
                return objects[best_match]
            end
        end

        search_column = 1
    end
end

local function find_last(include_separator)
    local cursor = vim.api.nvim_win_get_cursor(0)
    local lines = vim.api.nvim_buf_get_lines(0, 0, cursor[1], false)
    local search_column = cursor[2] + 1

    for line_number = #lines, 1, -1 do
        local line = lines[line_number]
        local offset = 1
        local start_column, end_column = line:find("[a-zA-Z0-9_-]+", offset)
        local objects = {}

        while start_column do
            add_word(objects, line, line_number, start_column, end_column, include_separator)
            offset = end_column + 1
            start_column, end_column = line:find("[a-zA-Z0-9_-]+", offset)
        end

        -- If we found some objects, select the best one
        if #objects > 0 then
            local best_match
            local best_distance

            for object_index, object in ipairs(objects) do
                local distance = (search_column or #line) - object["end_column"]

                if (not search_column or object["end_column"] < search_column) and (not best_distance or distance < best_distance) then
                    best_match = object_index
                    best_distance = distance
                end
            end

            if best_match then
                return objects[best_match]
            end
        end

        search_column = nil
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
            if requested == "closest" then
                -- TODO: Filter out lines that are not on the screen
                return find_closest(mode == "a")
            elseif requested == "next" then
                -- TODO: Filter out lines that are not on the screen
                return find_next(mode == "a")
            elseif requested == "last" then
                -- TODO: Filter out lines that are not on the screen
                return find_last(mode == "a")
            elseif requested == "every" then
                -- TODO: Filter out lines that are not on the screen
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
