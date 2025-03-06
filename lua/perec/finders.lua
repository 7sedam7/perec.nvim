local telescope_builtin = require("telescope.builtin")
local telescope_config = require("telescope.config").values
local pickers = require("telescope.pickers")
local make_entry = require("telescope.make_entry")
local finders = require("telescope.finders")
local previewers = require("telescope.previewers")
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")

local krafna = require("perec.krafna")

local M = {}

-- Function to find files using Telescope
-- @param opts (table) Optional parameters for finding files
--   opts.cwd (string) Directory to search in, defaults to PEREC_DIR
---  opts.engine: (string) Picker engine used. Defaults to "Telescope" and is the only supported one atm.
M.find_files = function(opts)
	return telescope_builtin.find_files(opts)
end

-- Function to search text in files using Telescope's live grep
-- @param opts (table) Optional parameters for grepping files
--   opts.cwd (string) Directory to search in, defaults to PEREC_DIR
---  opts.engine: (string) Picker engine used. Defaults to "Telescope" and is the only supported one atm.
M.grep_files = function(opts)
	return telescope_builtin.grep_string(opts)
end

-- Function to find files using Telescope
-- @param opts (table) Optional parameters for finding files
--   opts.cwd (string) Directory to search in, defaults to PEREC_DIR
---  opts.engine: (string) Picker engine used. Defaults to "Telescope" and is the only supported one atm.
M.find_queries = function(opts)
	pickers
		.new(opts, {
			finder = finders.new_table({
				results = krafna.find_queries(opts),
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
					opts.default_text = entry.value
					M.query_files(opts)
				end)
				return true
			end,
			previewer = previewers.new_buffer_previewer({
				title = "Query Preview",
				define_preview = function(self, entry, _status)
					local bufnr = self.state.bufnr
					local result = krafna.execute(entry.value, { cwd = opts.cwd, include_fields = "file.name" })

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
								if #field > 90 then
									field = field:sub(1, 90) .. "..."
								end
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

M.query_files = function(opts)
	local file_entry_maker = make_entry.gen_from_file(opts)

	pickers
		.new(opts, {
			finder = finders.new_dynamic({
				fn = function(prompt)
					if #prompt < 7 then -- "WHERE a" is a minimal query of size 7
						return {}
					end
					local results = krafna.execute(prompt, { cwd = opts.cwd, include_fields = "file.path" })

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

return M
