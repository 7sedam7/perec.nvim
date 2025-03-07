local qr = require("perec.objects.query_result")
local QueryResult = qr.QueryResult
local QueryResultRow = qr.QueryResultRow

local M = {}

-- local log = require("plenary.log"):new()
-- log.level = "debug"

--- helper
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

--- Parse the result of a krafna query
--- @param result string
--- @param metadata_fields string[]
--- @return QueryResult
local function from_tsv_str(result, metadata_fields)
	local result_lines = vim.split(result, "[\r\n]+", { trimempty = true })
	if #result_lines == 0 then
		return QueryResult:new({}, {})
	end

	local header = vim.split(result_lines[1], "\t", { trimempty = false })
	local rows = {}
	for i = 2, #result_lines do
		local line = result_lines[i]
		local split_line = vim.split(simplify_links_for_display(line), "\t", { trimempty = false })

		local metadata = {}
		for j, field in ipairs(metadata_fields) do
			metadata[field] = split_line[j]
		end

		table.insert(rows, QueryResultRow:new(vim.list_slice(split_line, #metadata_fields + 1), metadata))
		-- table.insert(rows, { metadata = metadata, data = vim.list_slice(split_line, #metadata_fields + 1) })
	end

	return QueryResult:new(header, rows)
end

--- Execute a krafna query
--- @param user_query string
--- @param opts table {metadata_fields: string[], include_fields: string|nil, cwd: string|nil}
--- @return QueryResult
M.execute = function(user_query, opts)
	opts = opts or {}
	local include_fields =
		table.concat(filter_empty({ table.concat(opts.metadata_fields or {}, ","), opts.include_fields or nil }), ",")

	local escaped_value = (user_query or ""):gsub("'", '"')
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

--- Find queries in the current directory
--- @param opts table {cwd: string}
--- @return string[]
M.find_queries = function(opts)
	local result = vim.fn.system("krafna --find " .. opts.cwd)
	return vim.split(result, "[\r\n]+", { trimempty = true })
end

return M
