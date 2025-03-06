local telescope_builtin = require("telescope.builtin")

-- Function to search text in files using Telescope's live grep
-- @param opts (table) Optional parameters for grepping files
--   opts.cwd (string) Directory to search in, defaults to PEREC_DIR
---  opts.engine: (string) Picker engine used. Defaults to "Telescope" and is the only supported one atm.
return function(opts)
	if opts.engine == "Telescope" then
		return telescope_builtin.grep_string(opts)
	end

	error("Invalid engine: " .. opts.engine, 2)
end
