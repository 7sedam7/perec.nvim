local M = {}

-- local log = require("plenary.log"):new()
-- log.level = "debug"

local function filter_empty(tbl)
	local result = {}
	for _, value in pairs(tbl) do
		if value ~= nil and vim.trim(value) ~= "" then
			table.insert(result, value)
		end
	end
	return result
end

local function simplify_links_for_display(input)
	return input:gsub("%[([^%]]+)%]%(([^%)]+)%)", function(text, _)
		return "[" .. text .. "]"
	end)
end

local function from_tsv_str(result, metadata_fields)
	local result_lines = vim.split(result, "[\r\n]+", { trimempty = true })

	local lines = {}
	for i, line in ipairs(result_lines) do
		local split_line = vim.split(simplify_links_for_display(line), "\t", { trimempty = false })

		local metadata = {}
		if i == 1 then
			metadata.is_header = true
		else
			for j, field in ipairs(metadata_fields) do
				metadata[field] = split_line[j]
			end
		end

		table.insert(lines, { metadata = metadata, data = vim.list_slice(split_line, #metadata_fields + 1) })
	end

	return lines
end

M.execute = function(krafna, opts)
	opts = opts or {}
	local include_fields =
		table.concat(filter_empty({ table.concat(opts.metadata_fields or {}, ","), opts.include_fields or nil }), ",")

	local escaped_value = (krafna or ""):gsub("'", '"')
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

	local result = vim.fn.system(query)
	return from_tsv_str(result, opts.metadata_fields or {})
end

M.find_queries = function(opts)
	local result = vim.fn.system("krafna --find " .. opts.cwd)
	return vim.split(result, "[\r\n]+", { trimempty = true })
end

return M
