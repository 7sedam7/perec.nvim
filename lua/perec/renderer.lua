local formatters = require("perec.formatters")

-- local log = require("plenary.log"):new()
-- log.level = "debug"

local M = {}

local ns_id = vim.api.nvim_create_namespace("krafna_preview")

--- Redraw the virtual text
--- @param query_results QueryResults
--- @param lookup_keys string|nil
M.redraw = function(query_results, lookup_keys)
	-- Clear existing virtual text
	vim.api.nvim_buf_clear_namespace(0, ns_id, 0, -1)

	if query_results:is_empty() then
		return
	end

	local line_nums = {}
	for k in pairs(query_results.results) do
		table.insert(line_nums, k)
	end
	table.sort(line_nums)

	for _, line_num in ipairs(line_nums) do
		M.render_krafna_result(query_results.results[line_num], 0, line_num - 1, lookup_keys)
	end
end

--- Render the krafna result as virtual text
--- @param query_result QueryResult
--- @param bufnr number
--- @param row number
--- @param lookup_keys string|nil
M.render_krafna_result = function(query_result, bufnr, row, lookup_keys)
	local formatted = formatters.format(query_result, lookup_keys)
	table.insert(formatted, {}) -- Add an empty line

	vim.api.nvim_buf_set_extmark(bufnr, ns_id, row + 1, 0, {
		virt_lines = formatted,
		virt_lines_above = false,
		ui_watched = true,
	})
end

M.render_template = function(template, variables)
	variables = variables or {}
	local tokens = {}
	local pos = 1
	local len = #template

	-- Parse template into tokens
	while pos <= len do
		local var_start = template:find("{{", pos, true)
		local code_start = template:find("{%", pos, true)
		local start, tag_type

		-- Determine next tag type
		if var_start and code_start then
			start = var_start < code_start and var_start or code_start
			tag_type = var_start < code_start and "var" or "code"
		else
			start = var_start or code_start
			tag_type = var_start and "var" or "code"
		end

		if not start then
			tokens[#tokens + 1] = { type = "text", value = template:sub(pos) }
			break
		end

		-- Add preceding text
		if start > pos then
			tokens[#tokens + 1] = { type = "text", value = template:sub(pos, start - 1) }
		end

		-- Find closing tag
		local end_, close
		if tag_type == "var" then
			end_, close = template:find("}}", start + 2, true)
		else
			end_, close = template:find("%}", start + 2, true)
		end

		if not end_ then
			tokens[#tokens + 1] = { type = "text", value = template:sub(start) }
			break
		end

		-- Extract content
		local content = vim.trim(template:sub(start + 2, end_ - 1))
		-- leave __cursor__ as is
		if tag_type == "var" and content == "__cursor__" then
			tag_type = "text"
			content = "{{" .. content .. "}}"
		end
		tokens[#tokens + 1] = { type = tag_type, value = content }
		pos = close + 1
	end

	-- Process tokens
	local output = {}
	local lookup_var = function(var_name, vars)
		local current = vars
		for _, part in pairs(vim.split(var_name, ".", { plain = true, trimempty = true })) do
			current = current[part]
			if current == nil then
				return nil
			end
		end
		return current
	end

	local env = {
		out = function(...)
			local args = { ... }
			for i = 1, select("#", ...) do
				output[#output + 1] = tostring(args[i])
			end
		end,
	}
	setmetatable(env, {
		__index = function(_, key)
			return variables[key] or _G[key]
		end,
		__newindex = variables,
	})

	for _, token in ipairs(tokens) do
		if token.type == "text" then
			output[#output + 1] = token.value
		elseif token.type == "var" then
			local value = lookup_var(token.value, variables)
			output[#output + 1] = tostring(value or "")
		elseif token.type == "code" then
			local chunk, err = load(token.value, "codeblock", "t", env)
			if not chunk then
				error("Code error: " .. err)
			end
			local success, msg = pcall(chunk)
			if not success then
				error("Execution error: " .. msg)
			end
		end
	end

	return table.concat(output)
end

return M
