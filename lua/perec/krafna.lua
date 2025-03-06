local M = {}

-- Function to execute SQL and get results
M.execute = function(krafna, opts)
	local escaped_value = (krafna or ""):gsub("'", '"')
	local include_fields = opts and opts.include_fields or ""
	local query = ""
	if string.find(string.upper(escaped_value), "FROM", 1, true) ~= nil then
		query = string.format("krafna '%s' --include-fields '%s'", escaped_value, include_fields)
	else
		query = string.format(
			"krafna '%s' --include-fields '%s' --from 'FRONTMATTER_DATA(\"%s\")'",
			escaped_value,
			include_fields,
			opts.cwd
		)
	end
	return vim.fn.system(query)
end

M.find_queries = function(opts)
	local result = vim.fn.system("krafna --find " .. opts.cwd)
	return vim.split(result, "[\r\n]+", { trimempty = true })
end

return M
