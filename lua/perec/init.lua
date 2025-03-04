local telescope_builtin = require("telescope.builtin")

local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local previewers = require("telescope.previewers")
local telescope_config = require("telescope.config").values
local make_entry = require("telescope.make_entry")
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")

local log = require("plenary.log"):new()
log.level = "debug"

local PEREC_DIR = vim.fn.expand(vim.fn.expand("$PEREC_DIR"))
local has_whichkey, whichkey = false, nil

local M = {}

M.find_files = function(opts)
	opts = opts or {}
	opts.cwd = opts.cwd or PEREC_DIR

	telescope_builtin.find_files(opts)
end

M.grep_files = function(opts)
	opts = opts or {}
	opts.cwd = opts.cwd or PEREC_DIR

	telescope_builtin.live_grep(opts)
end

-- M.search_notes = function (opts)
--   opts = opts or {}
--   opts.cwd = PEREC_DIR
--
-- end

M.find_queries = function(opts)
	opts = opts or {}
	opts.cwd = opts.cwd or PEREC_DIR

	local result = vim.fn.system("krafna --find " .. opts.cwd)
	local queries = vim.split(result, "[\r\n]+", { trimempty = true })

	pickers
		.new(opts, {
			finder = finders.new_table({
				results = queries,
				entry_maker = function(entry)
					return {
						value = entry,
						display = entry,
						ordinal = entry,
					}
				end,
			}),
			sorter = telescope_config.generic_sorter(opts),
			attach_mappings = function(prompt_bufnr)
				actions.select_default:replace(function()
					local entry = action_state.get_selected_entry()
					actions.close(prompt_bufnr)
					M.query_files({ default_text = entry.value })
				end)
				return true
			end,
			previewer = previewers.new_buffer_previewer({
				title = "Query Preview",
				define_preview = function(self, entry, _status)
					local bufnr = self.state.bufnr
					result = M.execute_krafna(entry.value, { include_fields = "file.name" })

					if vim.trim(result) == "" then
						vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "No files matching the query." })
						return
					end

					-- Try to parse as TSV first
					local has_tabs = result:find("\t")
					local lines = {}

					if has_tabs then
						local max_lengths = {}
						-- First pass to determine number of columns
						local num_columns = 0
						for line in result:gmatch("[^\r\n]+") do
							local count = select(2, line:gsub("\t", "")) + 1
							num_columns = math.max(num_columns, count)
						end

						-- Parse rows with proper empty cell handling
						for line in result:gmatch("[^\r\n]+") do
							local row = {}
							local prev_pos = 1
							for i = 1, num_columns do
								local pos = line:find("\t", prev_pos) or (#line + 1)
								local field = line:sub(prev_pos, pos - 1)
								table.insert(row, field)
								prev_pos = pos + 1
							end
							-- Track max column widths
							for i, field in ipairs(row) do
								max_lengths[i] = math.max(max_lengths[i] or 0, #field)
							end
							table.insert(lines, row)
						end

						-- Format as aligned table with header separator
						local formatted_lines = {}
						for idx, row in ipairs(lines) do
							local formatted_row = {}
							for i, field in ipairs(row) do
								table.insert(formatted_row, string.format("%-" .. (max_lengths[i] or 0) .. "s", field))
							end
							local line = table.concat(formatted_row, " | ")
							table.insert(formatted_lines, line)
							-- Add separator after header (first line)
							if idx == 1 then
								local sep = {}
								for i = 1, #row do
									table.insert(sep, string.rep("-", max_lengths[i]))
								end
								table.insert(formatted_lines, table.concat(sep, "-+-"))
							end
						end
						vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, formatted_lines)
					else
						-- Fall back to plain text display
						local plain_lines = {}
						for line in result:gmatch("[^\r\n]+") do
							table.insert(plain_lines, line)
						end
						vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, plain_lines)
					end
				end,
			}),
		})
		:find()
end

local function extract_code_under_cursor()
	-- Get cursor position
	local bufnr = vim.api.nvim_get_current_buf()
	local current_window = vim.api.nvim_get_current_win()
	local cursor_row = vim.api.nvim_win_get_cursor(current_window)[1]

	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

	-- Find the code block boundaries
	local start_line = nil
	local end_line = nil

	-- Scan up for start of block
	for i = cursor_row, 1, -1 do
		if lines[i]:gsub("%s+", "") == "```krafna" then
			start_line = i
			break
		end
	end

	-- Scan down for end of block
	if start_line then
		for i = cursor_row, #lines do
			if lines[i]:gsub("%s+", "") == "```" then
				end_line = i
				break
			end
		end
	end

	-- If we found a complete block
	if start_line and end_line then
		local code = table.concat(vim.list_slice(lines, start_line + 1, end_line - 1), "\n")

		code = code:gsub("\n", " "):gsub("\r\n", " ")

		return code
	end

	return nil
end

M.query_files = function(opts)
	opts = opts or {
		default_text = extract_code_under_cursor() or "WHERE ",
	}
	opts.cwd = opts.cwd or PEREC_DIR

	local file_entry_maker = make_entry.gen_from_file(opts)

	pickers
		.new(opts, {
			finder = finders.new_dynamic({
				fn = function(prompt)
					local escaped_value = (prompt or ""):gsub("'", "'\\''")
					if #escaped_value < 7 then -- "WHERE a" is a minimal query of size 7
						return {}
					end
					local results = M.execute_krafna(escaped_value, { include_fields = "file.path" })

					-- Parse TSV results
					local files = {}
					for line in results:gmatch("[^\r\n]+") do
						local path = line:match("^[^\t]+")
						if path then
							table.insert(files, path)
						end
					end
					if files and files[1] and files[1] == "file_path" then
						table.remove(files, 1)
						return files
					end
					-- return scan.scan_dir(opts.cwd)
					return {}
				end,
				entry_maker = function(entry)
					local file_entry = file_entry_maker(entry)
					file_entry.ordinal = vim.fn.fnamemodify(entry, ":t")
					return file_entry
				end,
			}),

			previewer = telescope_config.file_previewer(opts),
		})
		:find()
end

M.create_file = function(opts)
	opts = opts or {}
	opts.cwd = opts.cwd or PEREC_DIR
	-- Create a new document in the PEREC_DIR
	local filename = vim.fn.input("Enter document name: ")
	if not filename:match("%.md$") then
		filename = filename .. ".md"
	end
	local filepath = opts.cwd .. "/" .. filename

	-- Edit the file
	vim.cmd("edit " .. vim.fn.fnameescape(filepath))

	-- check if file exists
	local stat = vim.loop.fs_stat(filepath)
	if stat and stat.type == "file" then
	else
		-- Add template content
		local template = {
			"---",
			"tags:",
			"---",
			"# " .. vim.fn.fnamemodify(filepath, ":t:r"), -- Add filename as title
			"",
			"",
		}

		-- Set the lines in buffer
		vim.api.nvim_buf_set_lines(0, 0, -1, false, template)

		-- Move cursor to the end
		vim.api.nvim_win_set_cursor(0, { 6, 0 })

		-- Start in insert mode
		vim.cmd("startinsert")
	end
end

-- Check for required CLI tool
function M.check_cli_tool()
	local result = vim.fn.system("command -v krafna")

	if result == "" then
		error("CLI tool 'krafna' is not installed. Please install it before using this plugin.")
	end
end

--------------------------------------------------------------------------------
------ Krafna Preview (should extractc this to a separate file) ----------------
--------------------------------------------------------------------------------
local ns_id = vim.api.nvim_create_namespace("krafna_preview")

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

local function format_krafna_result_as_table(result_data)
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
	local data_rows = {}
	for i, line in ipairs(lines) do
		local folded_rows = split_and_fold_line(line, { highlighter = row_highlighter(i) })
		if folded_rows and #folded_rows > 1 then
			folds_exist = true
		end
		for _, row in ipairs(folded_rows) do
			table.insert(highlighters, table.remove(row))
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
		-- local data_line = vertical_pipe
		for col_idx, col_val in ipairs(row) do
			if col_val == "NULL" then
				table.insert(data_line, { " ", folds_exist and highlighters[i] or "Conceal" })
				table.insert(data_line, { col_val, "KrafnaTableNull" })
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

-- Function to execute SQL and get results
M.execute_krafna = function(krafna, opts)
	local escaped_value = (krafna or ""):gsub("'", "'\\''")
	local include_fields = opts and opts.include_fields or ""
	local query = ""
	if string.find(string.upper(escaped_value), "FROM", 1, true) ~= nil then
		query = string.format("krafna '%s' --include-fields '%s'", escaped_value, include_fields)
	else
		query = string.format(
			"krafna '%s' --include-fields '%s' --from 'FRONTMATTER_DATA(\"%s\")'",
			escaped_value,
			include_fields,
			PEREC_DIR
		)
	end
	return vim.fn.system(query)
end

local function extract_krafna(lines, start_line, end_line)
	local krafna = {}
	local i = start_line
	while i <= end_line do
		local line = lines[i]
		if line:match("^```%s*$") then
			break
		end
		table.insert(krafna, line)
		i = i + 1
	end
	return table.concat(krafna, "\n"), i - start_line + 1
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

local function num_to_string(num)
	local s = ""
	while num > 0 do
		num = num - 1
		local remainder = num % 26
		s = string.char(97 + remainder) .. s -- 'a' is ASCII 97
		num = math.floor(num / 26)
	end
	return s
end

krafna_quick_access = {}
local function set_quick_access(krafna_data)
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
	vim.keymap.set("n", "<leader>pd", M.render_quick_access, {
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
				data.metadata.keys = num_to_string(i)
				krafna_quick_access[data.metadata.keys] = data.metadata.file_path
				i = i + 1
			end
		end
	end
end

local function organise_krafna_result(result)
	local result_lines = vim.split(result, "[\r\n]+", { trimempty = true })

	local lines = {}
	for i, line in ipairs(result_lines) do
		local split_line = vim.split(line, "\t", { trimempty = false })
		local metadata = i ~= 1 and { file_path = split_line[1] } or nil
		table.insert(lines, { metadata = metadata, data = vim.list_slice(split_line, 2) })
	end

	return lines
end

local krafna_cache = {}
local function get_krafna(line, krafna_query, from_cache)
	from_cache = from_cache or false

	if not from_cache then
		local result = M.execute_krafna(krafna_query, { include_fields = "file.path" })
		local organized_results = organise_krafna_result(result)
		krafna_cache[line] = organized_results

		if #organized_results > 0 then
			set_quick_access(krafna_cache)
		end
	end

	return krafna_cache[line]
end

function M.update_virtual_text(opts)
	opts = opts or {}
	opts.from_cache = opts.from_cache or false
	-- Clear existing virtual text
	vim.api.nvim_buf_clear_namespace(0, ns_id, 0, -1)

	local blocks = find_krafna_blocks()
	for _, block in ipairs(blocks) do
		-- Check if cursor is not on the preview
		local block_end = block.start + block.num_lines
		-- if cursor_line < block.start or cursor_line > block_end then
		if true then
			local result = get_krafna(block.start, block.content, opts.from_cache)
			if result then
				local formatted = format_krafna_result_as_table(result)
				vim.api.nvim_buf_set_extmark(0, ns_id, block_end - 1, 0, {
					virt_lines = formatted,
					virt_lines_above = false,
				})
			end
		end
	end
end

local function add_keys_to_krafna_data()
	for _, krafna_code_block_data in pairs(krafna_cache) do
		for _, data in ipairs(krafna_code_block_data) do
			if data.metadata == nil then
				table.insert(data.data, 1, "")
			else
				table.insert(data.data, 1, data.metadata.keys)
			end
		end
	end
end

local function remove_first_row_from_krafna_data()
	for _, krafna_code_block_data in pairs(krafna_cache) do
		for _, data in ipairs(krafna_code_block_data) do
			table.remove(data.data, 1)
		end
	end
end

function get_char_with_timeout(timeout_ms)
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

function M.render_quick_access(opts)
	opts = opts or {}

	add_keys_to_krafna_data()
	M.update_virtual_text({ from_cache = true })

	vim.cmd("redraw")

	local lookup_keys = ""
	while true do
		local key = lookup_keys == "" and vim.fn.getchar() or get_char_with_timeout(500)
		if key == nil then
			if krafna_quick_access[lookup_keys] then
				vim.cmd("e " .. krafna_quick_access[lookup_keys])
			end
			break
		end
		local char = vim.fn.nr2char(key)

		if char == "\27" then -- ESC key
			break
		end

		lookup_keys = lookup_keys .. char
	end

	remove_first_row_from_krafna_data()
	M.update_virtual_text({ from_cache = true })
	-- end)

	return true
end

local function cleanup_buffer_maps_and_cache()
	if has_whichkey then
		whichkey.add({ { "<leader>pd", nil, desc = "", mode = "n", hidden = true } })
	end
	pcall(vim.keymap.del, "n", "<leader>pd")

	krafna_cache = {}
	krafna_quick_access = {}
end

local last_called = {}
local render_delay = 500
local function setup_rendering()
	local group = vim.api.nvim_create_augroup("KrafnaPreview", { clear = true })
	vim.api.nvim_set_hl(0, "KrafnaTableNull", { fg = "#FF0000" })
	vim.api.nvim_set_hl(0, "KrafnaTableRowEven", { reverse = true })
	-- vim.api.nvim_set_hl(0, "KrafnaTableRowEven", { fg = "#FFFFFF", bg = "#000010" })
	vim.api.nvim_create_autocmd(
		{ "BufEnter", "BufWinEnter", "WinEnter", "TabEnter", "BufNewFile", "BufWritePost", "BufReadPost", "FileType" },
		{
			group = group,
			pattern = { "*.md" },
			callback = function(event)
				local buff_id = vim.api.nvim_get_current_buf()
				local current_time = vim.loop.now()
				local last_time = last_called[buff_id] or 0

				-- Only proceed if enough time has passed since last call
				if (current_time - last_time) >= render_delay then
					-- Only trigger if the buffer is a real file or new file
					local bufnr = vim.api.nvim_get_current_buf()
					local buftype = vim.bo[bufnr].buftype
					local filename = vim.api.nvim_buf_get_name(bufnr)

					if buftype == "" and (filename ~= "" or vim.fn.exists("#BufNewFile<buffer>")) then
						last_called[buff_id] = current_time
						M.update_virtual_text()
					end
				end
			end,
		}
	)
	vim.api.nvim_create_autocmd({ "BufLeave" }, {
		group = group,
		pattern = { "*.md" },
		callback = function(event)
			-- reset krafna cache
			cleanup_buffer_maps_and_cache()
		end,
	})
end

-- Default configuration
local config = {
	group = {
		key = "<leader>p",
		desc = "Perec functions",
	},
	keymaps = {
		{
			mode = "n",
			key = "<leader>pf",
			action = M.find_files,
			desc = "Find files within Perec vault",
		},
		{
			mode = "n",
			key = "<leader>pg",
			action = M.grep_files,
			desc = "Grep files within Perec vault",
		},
		{
			mode = "n",
			key = "<leader>pp",
			action = M.find_queries,
			desc = "Find krafna queries within Perec vault",
		},
		{
			mode = "n",
			key = "<leader>pq",
			action = M.query_files,
			desc = "Query files within Perec vault",
		},
		{
			mode = "n",
			key = "<leader>pa",
			action = M.create_file,
			desc = "Create a buffer within Perec vault",
		},
	},
}

-- Setup function
function M.setup(opts)
	-- Default options
	opts = opts or { keys = {}, defaults = {} }
	defaults = vim.tbl_deep_extend("force", defaults, opts.defaults)

	PEREC_DIR = opts.cwd or PEREC_DIR

	-- Check CLI tool first
	M.check_cli_tool()

	-- Merge user options with defaults
	config = vim.tbl_deep_extend("force", config, opts.keys)

	-- Setup default keymaps
	has_whichkey, whichkey = pcall(require, "which-key")

	-- Use which-key if available
	if has_whichkey then
		whichkey.add({ { config.group.key, group = config.group.desc } })
	end
	for _, keymap in ipairs(config.keymaps) do
		local mode = keymap.mode or "n"
		local key = keymap.key
		local action = keymap.action
		local desc = keymap.desc

		-- Use which-key if available
		if has_whichkey then
			whichkey.add({ { key, action, desc = desc, mode = mode, hidden = false } })
		else
			-- Fallback to standard vim.keymap
			vim.keymap.set(mode, key, action, {
				desc = desc,
				noremap = keymap.noremap or true,
				silent = keymap.silent or true,
			})
		end
	end

	-- Setup rendering
	setup_rendering()

	return config
end

-- setup_rendering()
M.setup()

return M
