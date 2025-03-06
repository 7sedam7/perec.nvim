local has_whichkey, whichkey = pcall(require, "which-key")

local krafna = require("perec.krafna")

local M = {}

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

local function simplify_links_for_display(input)
	return input:gsub("%[([^%]]+)%]%(([^%)]+)%)", function(text, _)
		return "[" .. text .. "]"
	end)
end

local function format_krafna_result_as_table(result_data, lookup_keys)
	local lines = {}
	for _, line in ipairs(result_data) do
		table.insert(lines, line.data)
	end

	-- Check if we have any data
	if #lines == 0 then
		return { { { "| No data |", "Conceal" } } }
	end

	-- Split each line into columns
	local folds_exist = false
	local highlighters = {}
	local quick_access_keys = {}
	local data_rows = {}
	for i, line in ipairs(lines) do
		local folded_rows = split_and_fold_line(line, { highlighter = row_highlighter(i) })
		if folded_rows and #folded_rows > 1 then
			folds_exist = true
		end
		local quick_keys = lookup_keys
				and result_data[i].metadata
				and string.sub(result_data[i].metadata.keys, 1, #lookup_keys) == lookup_keys
				and result_data[i].metadata.keys
			or ""
		for _, row in ipairs(folded_rows) do
			table.insert(highlighters, table.remove(row))

			table.insert(quick_access_keys, quick_keys)
			quick_keys = ""

			table.insert(data_rows, row)
		end
	end

	-- Find the maximum width needed for each column
	local col_widths = {}

	-- Initialize widths from the first row (headers)
	for col_idx, col_val in ipairs(data_rows[1]) do
		col_widths[col_idx] = #col_val
	end

	-- Update widths based on data rows
	for i = 2, #data_rows do
		local row = data_rows[i]
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
	for col_idx, col_val in ipairs(data_rows[1]) do
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
	for i = 2, #data_rows do
		local row = data_rows[i]
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

local function extract_krafna(lines, start_line, end_line)
	local code_block = {}
	local i = start_line
	while i <= end_line do
		local line = lines[i]
		if line:match("^```%s*$") then
			break
		end
		table.insert(code_block, line)
		i = i + 1
	end
	return table.concat(code_block, "\n"), i - start_line + 1
end

local function find_krafna_blocks()
	local blocks = {}
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)

	for i, line in ipairs(lines) do
		if line:match("^```%s*krafna.*$") then
			local content, num_lines = extract_krafna(lines, i + 1, #lines)
			table.insert(blocks, {
				start = i,
				content = content,
				num_lines = num_lines,
			})
		end
	end
	return blocks
end

local function generate_keymap_keys(num)
	local s = ""
	while num > 0 do
		num = num - 1
		local remainder = num % 26
		s = string.char(97 + remainder) .. s -- 'a' is ASCII 97
		num = math.floor(num / 26)
	end
	return s
end

local krafna_cache = {}
local krafna_quick_access = {}
local krafna_quick_access_keys = {}

local function update_krafna_quick_access_keys(hash, keys)
	keys = keys:sub(1, #keys - 1)
	for i = 1, #keys do
		local prefix = keys:sub(1, i)
		hash[prefix] = true
	end
end

local function get_char_with_timeout(timeout_ms)
	local char = nil
	vim.fn.wait(timeout_ms, function()
		local _char = vim.fn.getchar(0)
		if _char ~= 0 then
			char = _char
			return true
		end
		return false
	end)
	return char
end

local function render_quick_access(opts)
	opts = opts or {}

	local lookup_keys = ""
	while true do
		M.update_virtual_text({ from_cache = true, lookup_keys = lookup_keys })
		vim.cmd("redraw")

		local key = get_char_with_timeout(1000)
		if key == nil then
			break
		end
		local char = vim.fn.nr2char(key)

		if char == "\27" then -- ESC key
			break
		end

		lookup_keys = lookup_keys .. char
		if krafna_quick_access_keys[lookup_keys] ~= true then
			break
		end
	end

	M.update_virtual_text({ from_cache = true })

	if krafna_quick_access[lookup_keys] then
		vim.cmd("e " .. krafna_quick_access[lookup_keys])
	end

	return true
end

local function set_quick_access(krafna_data)
	if krafna_data == nil or next(krafna_cache) == nil then
		return
	end

	local line_nums = {}
	for k in pairs(krafna_data) do
		table.insert(line_nums, k)
	end
	table.sort(line_nums)

	-- Set keymaps
	if has_whichkey then
		whichkey.add({
			{ "<leader>pd", nil, desc = "Go to file from query preview", mode = "n", hidden = false },
		})
	end
	vim.keymap.set("n", "<leader>pd", render_quick_access, {
		desc = "Go to file from query preview",
		noremap = true,
		silent = true,
	})

	-- Generate key
	local i = 1
	for _, line_num in ipairs(line_nums) do
		local krafna_code_block_data = krafna_data[line_num]
		for _, data in ipairs(krafna_code_block_data) do
			if data.metadata ~= nil then
				data.metadata.keys = generate_keymap_keys(i)
				krafna_quick_access[data.metadata.keys] = data.metadata.file_path
				update_krafna_quick_access_keys(krafna_quick_access_keys, data.metadata.keys)
				i = i + 1
			end
		end
	end
end

local function organise_krafna_result(result)
	local result_lines = vim.split(result, "[\r\n]+", { trimempty = true })

	local lines = {}
	for i, line in ipairs(result_lines) do
		local split_line = vim.split(simplify_links_for_display(line), "\t", { trimempty = false })
		local metadata = i ~= 1 and { file_path = split_line[1] } or nil
		table.insert(lines, { metadata = metadata, data = vim.list_slice(split_line, 2) })
	end

	return lines
end

local ns_id = vim.api.nvim_create_namespace("krafna_preview")

M.update_virtual_text = function(opts)
	opts = opts or {}
	opts.from_cache = opts.from_cache or false

	-- Clear existing virtual text
	vim.api.nvim_buf_clear_namespace(0, ns_id, 0, -1)

	local blocks = find_krafna_blocks()
	for _, block in ipairs(blocks) do
		local block_end = block.start + block.num_lines

		if not opts.from_cache then
			krafna_cache[block.start] =
				organise_krafna_result(krafna.execute(block.content, { cwd = opts.cwd, include_fields = "file.path" }))

			if krafna_cache[block.start] and next(krafna_cache[block.start]) then
				set_quick_access(krafna_cache)
			end
		end
		if krafna_cache[block.start] and #krafna_cache[block.start] > 0 then
			local formatted = format_krafna_result_as_table(krafna_cache[block.start], opts.lookup_keys)
			vim.api.nvim_buf_set_extmark(0, ns_id, block_end - 1, 0, {
				virt_lines = formatted,
				virt_lines_above = false,
				ui_watched = true,
			})
		end
	end
end

M.cleanup_state = function()
	krafna_cache = {}
	krafna_quick_access = {}
	krafna_quick_access_keys = {}
end

return M
