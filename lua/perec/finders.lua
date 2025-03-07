local telescope_builtin = require("telescope.builtin")
local telescope_config = require("telescope.config").values
local pickers = require("telescope.pickers")
local make_entry = require("telescope.make_entry")
local finders = require("telescope.finders")
local previewers = require("telescope.previewers")
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")

local krafna = require("perec.krafna")
local renderer = require("perec.renderer")

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
				define_preview = function(self, entry, _)
					local bufnr = self.state.bufnr
					local result = krafna.execute(entry.value, { cwd = opts.cwd })

					renderer.render_krafna_result(result, bufnr, 0, nil)
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
					local result = krafna.execute(prompt, { cwd = opts.cwd, metadata_fields = { "file.path" } })

					local files = {}
					for _, row in pairs(result.rows) do
						table.insert(files, row.metadata["file.path"])
					end
					if #files > 1 and not string.find(files[1], "error") then
						table.remove(files, 1)
					end

					return files
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
