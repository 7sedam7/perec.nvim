local telescope_builtin = require("telescope.builtin")

-- Function to find files using Telescope
-- @param opts (table) Optional parameters for finding files
--   opts.cwd (string) Directory to search in, defaults to PEREC_DIR
---  opts.engine: (string) Picker engine used. Defaults to "Telescope" and is the only supported one atm.
return function(opts)
	local log = require("plenary.log"):new()
	log.level = "debug"
	log.debug("KIFLA")
	if opts.engine == "Telescope" then
		return telescope_builtin.find_files(opts)
	end

	error("Invalid engine: " .. opts.engine, 2)
end
