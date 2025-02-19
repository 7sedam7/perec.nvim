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
					-- Escape single quotes in the query value
					local escaped_value = entry.value:gsub("'", "'\\''")
					-- Build the command with proper shell escaping
					local query = string.format(
						"krafna '%s' --include-fields 'file.name' --from 'FRONTMATTER_DATA(\"%s\")'",
						escaped_value,
						opts.cwd:gsub("'", "'\\''")
					)
					result = vim.fn.system(query)

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
					-- -- Build the command with proper shell escaping
					local query = string.format(
						"krafna '%s' --include-fields 'file.path' --from 'FRONTMATTER_DATA(\"%s\")'",
						escaped_value,
						opts.cwd:gsub("'", "'\\''") -- TODO: remove this escaping
					)
					local results = vim.fn.system(query)

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
					log.debug(file_entry.ordinal)
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
			"```",
			"```",
			"# " .. vim.fn.fnamemodify(filepath, ":t:r"), -- Add filename as title
			"",
			"",
		}

		-- Set the lines in buffer
		vim.api.nvim_buf_set_lines(0, 0, -1, false, template)

		-- Move cursor to the end
		vim.api.nvim_win_set_cursor(0, { 5, 0 })

		-- Start in insert mode
		vim.cmd("startinsert")
	end
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

-- Check for required CLI tool
function M.check_cli_tool()
	local result = vim.fn.system("command -v krafna")

	if result == "" then
		error("CLI tool 'krafna' is not installed. Please install it before using this plugin.")
	end
end

-- log.debug(scan.scan_dir('.', { hidden = true, depth = 5 }))
-- M.find_files()
-- M.grep_files()
-- M.find_queries()
-- M.query_files()
-- M.create_file()

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

local function format_krafna_result(tsv_data)
	-- Split the input into lines
	local lines = {}
	for line in string.gmatch(tsv_data, "[^\n]+") do
		table.insert(lines, line)
	end

	-- Check if we have any data
	if #lines == 0 then
		return { { { "| No data |", "Conceal" } } }
	end

	-- Split each line into columns
	local data_rows = {}
	for _, line in ipairs(lines) do
		local cols = {}
		for col in string.gmatch(line, "[^\t]+") do
			table.insert(cols, col)
		end
		table.insert(data_rows, cols)
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
				table.insert(data_line, { " ", "Conceal" })
				table.insert(data_line, { col_val, "KrafnaTableNull" })
				table.insert(
					data_line,
					{ string.rep(" ", col_widths[col_idx] - #col_val + 1) .. vertical_pipe, "Conceal" }
				)
			else
				table.insert(data_line, {
					" " .. col_val .. string.rep(" ", col_widths[col_idx] - #col_val + 1) .. vertical_pipe,
					"Conceal",
				})
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
local function execute_krafna(krafna)
	local escaped_value = (krafna or ""):gsub("'", "'\\''")
	local query = string.format("krafna '%s' --from 'FRONTMATTER_DATA(\"%s\")'", escaped_value, PEREC_DIR)
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

function M.update_virtual_text()
	local mode = vim.api.nvim_get_mode().mode
	local cursor = vim.api.nvim_win_get_cursor(0)
	local cursor_line = cursor[1]

	-- Clear existing virtual text
	vim.api.nvim_buf_clear_namespace(0, ns_id, 0, -1)

	-- Only show previews in normal mode
	-- if mode ~= "n" then
	-- 	return
	-- end

	local blocks = find_krafna_blocks()
	for _, block in ipairs(blocks) do
		-- Check if cursor is not on the preview
		local block_end = block.start + block.num_lines
		-- if cursor_line < block.start or cursor_line > block_end then
		if true then
			local result = execute_krafna(block.content)
			if result then
				local formatted = format_krafna_result(result)
				vim.api.nvim_buf_set_extmark(0, ns_id, block_end - 1, 0, {
					virt_lines = formatted,
					virt_lines_above = false,
				})
			end
		end
	end
end

local last_called = 0
local render_delay = 100
local function setup_rendering()
	local group = vim.api.nvim_create_augroup("KrafnaPreview", { clear = true })
	vim.api.nvim_set_hl(0, "KrafnaTableNull", { fg = "#FF0000" })
	vim.api.nvim_create_autocmd(
		{ "BufEnter", "BufWinEnter", "WinEnter", "TabEnter", "BufNewFile", "BufWritePost", "BufReadPost" },
		{
			group = group,
			pattern = { "*.md" },
			callback = function()
				local current_time = vim.loop.now()

				-- Only proceed if enough time has passed since last call
				if (current_time - last_called) >= render_delay then
					-- Only trigger if the buffer is a real file or new file
					local bufnr = vim.api.nvim_get_current_buf()
					local buftype = vim.bo[bufnr].buftype
					local filename = vim.api.nvim_buf_get_name(bufnr)

					if buftype == "" and (filename ~= "" or vim.fn.exists("#BufNewFile<buffer>")) then
						last_called = current_time
						M.update_virtual_text()
					end
				end
			end,
		}
	)
end

-- Setup function
function M.setup(opts)
	-- Default options
	opts = opts or {}

	-- Check CLI tool first
	M.check_cli_tool()

	-- Merge user options with defaults
	config = vim.tbl_deep_extend("force", config, opts)

	-- Setup default keymaps
	local has_whichkey, whichkey = pcall(require, "which-key")

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
			whichkey.add({ { key, action, desc = desc, mode = mode } })
		else
			-- Fallback to standard vim.keymap
			vim.keymap.set(mode, key, action, {
				desc = desc,
				silent = keymap.silent or true,
			})
		end
	end

	-- Setup rendering
	setup_rendering()

	return config
end

-- setup_rendering()

return M
