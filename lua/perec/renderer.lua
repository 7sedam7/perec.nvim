local has_whichkey, whichkey = pcall(require, "which-key")

local krafna = require("perec.krafna")
local formatters = require("perec.formatters")

-- local log = require("plenary.log"):new()
-- log.level = "debug"

local M = {}

local ns_id = vim.api.nvim_create_namespace("krafna_preview")

local function redraw(krafna_blocks, lookup_keys)
	-- Clear existing virtual text
	vim.api.nvim_buf_clear_namespace(0, ns_id, 0, -1)

	if krafna_blocks == nil or next(krafna_blocks) == nil then
		return
	end

	local line_nums = {}
	for k in pairs(krafna_blocks) do
		table.insert(line_nums, k)
	end
	table.sort(line_nums)

	for _, line_num in ipairs(line_nums) do
		M.render_krafna_result(krafna_blocks[line_num], 0, line_num - 1, lookup_keys)
	end
end

local function extract_krafna(lines, start_line, end_line)
	local code_block = {}
	local i = start_line
	while i <= end_line do
		local line = lines[i]
		if line:match("^```%s*$") then
			break
		end
		table.insert(code_block, line)
		i = i + 1
	end
	return table.concat(code_block, "\n"), i - start_line + 1
end

local function find_krafna_blocks()
	local blocks = {}
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)

	for i, line in ipairs(lines) do
		if line:match("^```%s*krafna.*$") then
			local content, num_lines = extract_krafna(lines, i + 1, #lines)
			table.insert(blocks, {
				start = i,
				content = content,
				num_lines = num_lines,
			})
		end
	end
	return blocks
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

local krafna_cache = {}
local krafna_quick_access = {}
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

local function set_quick_access(krafna_data)
	if krafna_data == nil or next(krafna_data) == nil then
		return
	end

	local line_nums = {}
	for k in pairs(krafna_data) do
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
		local krafna_code_block_data = krafna_data[line_num]
		for _, data in ipairs(krafna_code_block_data) do
			if data.metadata and not data.metadata.is_header then
				data.metadata.keys = generate_keymap_keys(i)
				krafna_quick_access[data.metadata.keys] = data.metadata["file.path"]
				update_krafna_quick_access_keys(krafna_quick_access_keys, data.metadata.keys)
				i = i + 1
			end
		end
	end
end

M.render_krafna_result = function(result, bufnr, row, lookup_keys)
	local formatted = formatters.krafna_result_as_table(result, lookup_keys)
	vim.api.nvim_buf_set_extmark(bufnr, ns_id, row, 0, {
		virt_lines = formatted,
		virt_lines_above = false,
		ui_watched = true,
	})
end

M.update_virtual_text = function(opts)
	opts = opts or {}
	opts.from_cache = opts.from_cache or false

	local blocks = find_krafna_blocks()

	for _, block in ipairs(blocks) do
		local block_end = block.start + block.num_lines

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
