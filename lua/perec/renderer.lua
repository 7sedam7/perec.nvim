local formatters = require("perec.formatters")

local log = require("plenary.log"):new()
log.level = "debug"

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
	vim.api.nvim_buf_set_extmark(bufnr, ns_id, row, 0, {
		virt_lines = formatted,
		virt_lines_above = false,
		ui_watched = true,
	})
end

return M
