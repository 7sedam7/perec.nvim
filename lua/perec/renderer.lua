local has_whichkey, whichkey = pcall(require, "which-key")

local krafna = require("perec.krafna")
local formatters = require("perec.formatters")
local CodeBlock = require("perec.objects.code_block")

local log = require("plenary.log"):new()
log.level = "debug"

local M = {}

local ns_id = vim.api.nvim_create_namespace("krafna_preview")

--- Redraw the virtual text
--- @param query_results table<number, QueryResult> Table with line numbers as keys and arrays of QueryResults as values
--- @param lookup_keys string|nil
local function redraw(query_results, lookup_keys)
	-- Clear existing virtual text
	vim.api.nvim_buf_clear_namespace(0, ns_id, 0, -1)

	if query_results == nil or next(query_results) == nil then
		return
	end

	local line_nums = {}
	for k in pairs(query_results) do
		table.insert(line_nums, k)
	end
	table.sort(line_nums)

	for _, line_num in ipairs(line_nums) do
		M.render_krafna_result(query_results[line_num], 0, line_num - 1, lookup_keys)
	end
end

local function generate_keymap_keys(num)
	local s = ""
	while num > 0 do
		num = num - 1
		local remainder = num % 26
		s = string.char(97 + remainder) .. s -- 'a' is ASCII 97
		num = math.floor(num / 26)
	end
	return s
end

--- @type table<number, QueryResult>
local krafna_cache = {}
--- @type table<string, string>
local krafna_quick_access = {}
--- @type table<string, boolean>
local krafna_quick_access_keys = {}

local function update_krafna_quick_access_keys(hash, keys)
	keys = keys:sub(1, #keys - 1)
	for i = 1, #keys do
		local prefix = keys:sub(1, i)
		hash[prefix] = true
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

local function render_quick_access(opts)
	opts = opts or {}

	local lookup_keys = ""
	while true do
		redraw(krafna_cache, lookup_keys)
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
		if krafna_quick_access_keys[lookup_keys] ~= true then
			break
		end
	end

	redraw(krafna_cache)

	if krafna_quick_access[lookup_keys] then
		vim.cmd("e " .. krafna_quick_access[lookup_keys])
	end

	return true
end

--- Set the quick access keymaps
--- @param query_results table<number, QueryResult> Table with line numbers as keys and arrays of QueryResults as values
local function set_quick_access(query_results)
	if query_results == nil or next(query_results) == nil then
		return
	end

	local line_nums = {}
	for k in pairs(query_results) do
		table.insert(line_nums, k)
	end
	table.sort(line_nums)

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

	-- Generate key
	local i = 1
	for _, line_num in ipairs(line_nums) do
		local query_result = query_results[line_num]
		for _, row in ipairs(query_result.rows) do
			if row.metadata then
				row.metadata.keys = generate_keymap_keys(i)
				krafna_quick_access[row.metadata.keys] = row.metadata["file.path"]
				update_krafna_quick_access_keys(krafna_quick_access_keys, row.metadata.keys)
				i = i + 1
			end
		end
	end
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

M.update_virtual_text = function(opts)
	opts = opts or {}
	opts.from_cache = opts.from_cache or false

	local blocks = CodeBlock.find_within_buffer("krafna")

	for _, block in ipairs(blocks) do
		local block_end = block.start_line + block.num_lines

		if not opts.from_cache then
			krafna_cache[block_end] =
				krafna.execute(block.content, { cwd = opts.cwd, metadata_fields = { "file.path" } })

			if krafna_cache[block_end] and next(krafna_cache[block_end]) then
				set_quick_access(krafna_cache)
			end
		end
	end
	redraw(krafna_cache, opts.lookup_keys)
end

M.cleanup_state = function()
	krafna_cache = {}
	krafna_quick_access = {}
	krafna_quick_access_keys = {}
end

return M
