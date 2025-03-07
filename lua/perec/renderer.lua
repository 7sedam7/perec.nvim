local has_whichkey, whichkey = pcall(require, "which-key")

local krafna = require("perec.krafna")
local formatters = require("perec.formatters")
local CodeBlock = require("perec.objects.code_block")
local QueryResults = require("perec.objects.query_result").QueryResults

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

local function get_char_with_timeout(timeout_ms)
	local char = nil
	vim.fn.wait(timeout_ms, function()
		local _char = vim.fn.getchar(0)
		if _char ~= 0 then
			char = _char
			return true
		end
		return false
	end)
	return char
end

--- Render the krafna result as virtual text
--- @param query_result QueryResult
--- @param bufnr number
--- @param row number
--- @param lookup_keys string|nil
M.render_krafna_result = function(query_result, bufnr, row, lookup_keys)
	local formatted = formatters.krafna_result_as_table(query_result, lookup_keys)
	vim.api.nvim_buf_set_extmark(bufnr, ns_id, row, 0, {
		virt_lines = formatted,
		virt_lines_above = false,
		ui_watched = true,
	})
end

--- @type QueryResults
local query_results = nil

local function render_quick_access(opts)
	opts = opts or {}

	local lookup_keys = ""
	while true do
		M.redraw(query_results, lookup_keys)
		vim.cmd("redraw")

		local key = get_char_with_timeout(1000)
		if key == nil then
			break
		end
		local char = vim.fn.nr2char(key)

		if char == "\27" then -- ESC key
			break
		end

		lookup_keys = lookup_keys .. char
		if query_results:only_match(lookup_keys) then
			break
		end
	end

	M.redraw(query_results)

	if query_results.keys_to_paths[lookup_keys] then
		vim.cmd("e " .. query_results.keys_to_paths[lookup_keys])
	end

	return true
end

M.update_virtual_text = function(opts)
	opts = opts or {}
	opts.from_cache = opts.from_cache or false

	query_results = QueryResults:new()
	local blocks = CodeBlock.find_within_buffer("krafna")

	for _, block in ipairs(blocks) do
		local block_end = block.start_line + block.num_lines

		if not opts.from_cache then
			local query_result = query_results:set(
				block_end,
				krafna.execute(block.content, { cwd = opts.cwd, metadata_fields = { "file.path" } })
			)

			if not query_result:is_empty() then
				-- Set keymaps
				if has_whichkey then
					whichkey.add({
						{ "<leader>pd", nil, desc = "Go to file from query preview", mode = "n", hidden = false },
					})
				end
				vim.keymap.set("n", "<leader>pd", render_quick_access, {
					desc = "Go to file from query preview",
					noremap = true,
					silent = true,
				})
			end
		end
	end
	M.redraw(query_results, opts.lookup_keys)
end

M.cleanup_state = function()
	query_results:clear()
end

return M
