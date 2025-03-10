local M = {}

-- local log = require("plenary.log"):new()
-- log.level = "debug"

local top_left_pipe = "┌"
local top_center_pipe = "┬"
local top_right_pipe = "┐"
local middle_left_pipe = "├"
local middle_center_pipe = "┼"
local middle_right_pipe = "┤"
local bottom_left_pipe = "└"
local bottom_center_pipe = "┴"
local bottom_right_pipe = "┘"
local vertical_pipe = "│"
local horizontal_pipe = "─"

local defaults = {
	max_length = 80,
	alternate_highlighter = "KrafnaTableRowEven",
}

-- TODO: Don't fold in the middle of a word and link, add link styling
--- Split a line into multiple lines if it exceeds max_length
--- @param columns table {string}
--- @param opts table { max_length: number, highlighter: string }
--- @return table { { string, string } }
local function split_and_fold_line(columns, opts)
	columns = vim.deepcopy(columns, true)

	local max_length = opts and opts.max_length or defaults.max_length
	local highlighter = opts and opts.highlighter or "Conceal"
	table.insert(columns, highlighter)
	local result = { columns } -- First row with original data
	local has_long_columns = false

	-- Check if any column exceeds max_length
	for _, col in ipairs(columns) do
		if #col > max_length then
			has_long_columns = true
			break
		end
	end

	-- If no long columns, return the original row
	if not has_long_columns then
		return { columns }
	end

	-- First, find all columns that need folding
	local long_columns = {}
	for i, col in ipairs(columns) do
		if #col > max_length then
			table.insert(long_columns, { index = i, content = col })
			-- Initialize with first chunk
			result[1][i] = string.sub(col, 1, max_length)
		end
	end

	-- Then create folded rows for all long columns together
	if #long_columns > 0 then
		local all_done = false
		local row_index = 1

		while not all_done do
			all_done = true
			local need_new_row = false

			-- Check if any column still has content to fold
			for _, col_info in ipairs(long_columns) do
				local i = col_info.index
				local col = col_info.content

				local start_pos = (row_index * max_length) + 1
				local chunk = string.sub(col, start_pos, start_pos + max_length - 1)

				if #chunk > 0 then
					need_new_row = true
					all_done = false
				end
			end

			-- If needed, create a new row and fill it
			if need_new_row then
				local new_row = {}
				for j = 1, #columns - 1 do
					new_row[j] = "" -- Fill with empty strings
				end
				table.insert(new_row, highlighter) -- Add highlighter

				-- Fill in the next chunk for each long column
				for _, col_info in ipairs(long_columns) do
					local i = col_info.index
					local col = col_info.content

					local start_pos = (row_index * max_length) + 1
					local chunk = string.sub(col, start_pos, start_pos + max_length - 1)
					if #chunk > 0 then
						new_row[i] = chunk
					end
				end

				table.insert(result, new_row)
				row_index = row_index + 1
			end
		end
	end

	return result
end

local function row_highlighter(row_idx)
	if row_idx % 2 == 0 then
		return defaults.alternate_highlighter
	else
		return "Conceal"
	end
end

--- Convert a QueryResult to a extmark formatted table
--- @param query_result QueryResult
--- @param lookup_keys string|nil
--- @return table { { { string, string } } }
local function as_table(query_result, lookup_keys)
	if query_result == nil then
		error("QueryResult is nil")
	end

	if query_result:is_empty() then
		return { { { "| No data |", "Conceal" } } }
	end

	-- Split each line into columns
	local folds_exist = false
	local highlighters = {}
	local quick_access_keys = {}
	local data_rows = {}
	for i, row in ipairs(query_result.rows) do
		local folded_rows = split_and_fold_line(row.data, { highlighter = row_highlighter(i) })
		if folded_rows and #folded_rows > 1 then
			folds_exist = true
		end
		local quick_keys = lookup_keys
				and row.metadata
				and row.metadata.keys
				and string.sub(row.metadata.keys, 1, #lookup_keys) == lookup_keys
				and row.metadata.keys
			or ""
		for _, folded_row in ipairs(folded_rows) do
			table.insert(highlighters, table.remove(folded_row))

			table.insert(quick_access_keys, quick_keys)
			quick_keys = ""

			table.insert(data_rows, folded_row)
		end
	end

	-- Find the maximum width needed for each column
	local col_widths = {}

	-- Initialize widths from the first row (headers)
	for col_idx, col_val in pairs(query_result.header) do
		col_widths[col_idx] = #col_val
	end

	-- Update widths based on data rows
	for _, row in pairs(data_rows) do
		for col_idx, col_val in ipairs(row) do
			if col_idx <= #col_widths then
				col_widths[col_idx] = math.max(col_widths[col_idx], #col_val)
			else
				col_widths[col_idx] = #col_val
			end
		end
	end

	-- Format the table
	local result = {}

	-- Top row
	local top_line = top_left_pipe
	for i, width in ipairs(col_widths) do
		if i == #col_widths then
			top_line = top_line .. string.rep(horizontal_pipe, width + 2) .. top_right_pipe
		else
			top_line = top_line .. string.rep(horizontal_pipe, width + 2) .. top_center_pipe
		end
	end
	table.insert(result, { { top_line, "RenderMarkdownTableHead" } })

	-- Header row (first line of TSV)
	local header_line = vertical_pipe
	for col_idx, col_val in pairs(query_result.header) do
		header_line = header_line
			.. " "
			.. col_val
			.. string.rep(" ", col_widths[col_idx] - #col_val + 1)
			.. vertical_pipe
	end
	table.insert(result, { { header_line, "RenderMarkdownTableHead" } })

	-- Separator row
	local separator_line = middle_left_pipe
	for i, width in ipairs(col_widths) do
		if i == #col_widths then
			separator_line = separator_line .. string.rep(horizontal_pipe, width + 2) .. middle_right_pipe
		else
			separator_line = separator_line .. string.rep(horizontal_pipe, width + 2) .. middle_center_pipe
		end
	end
	table.insert(result, { { separator_line, "RenderMarkdownTableHead" } })

	-- Data rows (skip first row which is the header)
	for i, row in pairs(data_rows) do
		local data_line = { { vertical_pipe, "Conceal" } }
		for col_idx, col_val in ipairs(row) do
			local col_highlighter = col_val == "NULL" and "KrafnaTableNull" or "Conceal"
			if folds_exist then
				col_highlighter = highlighters[i]
			end
			local quick_keys = quick_access_keys[i]
			if col_idx == 1 and quick_keys ~= "" then
				table.insert(data_line, { " ", folds_exist and highlighters[i] or "Conceal" })
				table.insert(data_line, { quick_keys, "HopNextKey" })
				table.insert(data_line, { string.sub(col_val, #quick_keys + 1), col_highlighter })
				table.insert(data_line, {
					string.rep(" ", col_widths[col_idx] - #col_val + 1),
					folds_exist and highlighters[i] or "Conceal",
				})
				table.insert(data_line, { vertical_pipe, "Conceal" })
			elseif col_val == "NULL" then
				table.insert(data_line, { " ", folds_exist and highlighters[i] or "Conceal" })
				table.insert(data_line, { col_val, col_highlighter })
				table.insert(data_line, {
					string.rep(" ", col_widths[col_idx] - #col_val + 1),
					folds_exist and highlighters[i] or "Conceal",
				})
				table.insert(data_line, { vertical_pipe, "Conceal" })
			else
				table.insert(data_line, {
					" " .. col_val .. string.rep(" ", col_widths[col_idx] - #col_val + 1),
					folds_exist and highlighters[i] or "Conceal",
				})
				table.insert(data_line, { vertical_pipe, "Conceal" })
			end
		end
		table.insert(result, data_line)
	end

	-- Bottom row
	local bottom_line = bottom_left_pipe
	for i, width in ipairs(col_widths) do
		if i == #col_widths then
			bottom_line = bottom_line .. string.rep(horizontal_pipe, width + 2) .. bottom_right_pipe
		else
			bottom_line = bottom_line .. string.rep(horizontal_pipe, width + 2) .. bottom_center_pipe
		end
	end
	table.insert(result, { { bottom_line, "Conceal" } })

	return result
end

-- TODO: Quick access should take you to the exact line where todo is
--- Convert a QueryResult to a extmark formatted table
--- @param query_result QueryResult
--- @param lookup_keys string|nil
--- @return table { { { string, string } } }
local function as_todo(query_result, lookup_keys)
	if query_result == nil then
		error("QueryResult is nil")
	end

	if query_result:is_empty() then
		return { { { "| No data |", "Conceal" } } }
	end

	local result = {}

	for i, row in ipairs(query_result.rows) do
		local folded_rows = split_and_fold_line(row.data, { highlighter = row_highlighter(i) })
		for j, folded_row in pairs(folded_rows) do
			if j == 1 then
				local content = folded_row[2]
				local quick_keys = lookup_keys
						and row.metadata
						and row.metadata.keys
						and string.sub(row.metadata.keys, 1, #lookup_keys) == lookup_keys
						and row.metadata.keys
					or ""
				if quick_keys ~= "" then
					content = string.sub(content, #quick_keys + 1)
				end

				local result_row = {
					row.data[1] == "true" and { "󰱒 ", "RenderMarkdownChecked" }
						or { "󰄱 ", "RenderMarkdownUnchecked" },
					{ "\t", "Conceal" },
				}
				table.insert(result_row, { quick_keys, "HopNextKey" })
				table.insert(result_row, { content, folded_row[3] })

				table.insert(result, result_row)
			else
				table.insert(result, {
					{ "\t", "Conceal" },
					{ folded_row[2], folded_row[3] },
				})
			end
		end
	end

	return result
end

--- Convert a QueryResult to a extmark formatted table
--- @param query_result QueryResult
--- @param lookup_keys string|nil
--- @return table
M.format = function(query_result, lookup_keys)
	if query_result and query_result.header and #query_result.header == 2 and query_result.header[1] == "checked" then
		return as_todo(query_result, lookup_keys)
	end

	return as_table(query_result, lookup_keys)
end

return M
