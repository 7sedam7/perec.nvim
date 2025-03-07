local State = require("perec.state")

---@class CodeBlock
---@field start_line number The starting line of the code block
---@field content string The content of the code block
---@field num_lines number The number of lines in the code block
local CodeBlock = {}
CodeBlock.__index = CodeBlock

function CodeBlock:new(start_line, content, num_lines)
	local obj = setmetatable({}, self)

	obj.start_line = start_line
	obj.content = content
	obj.num_lines = num_lines

	return obj
end

---@param lang string The programming language identifier
---@return CodeBlock[] A list of code blocks
CodeBlock.find_within_buffer = function(lang)
	local blocks = {}
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)

	local code_block = {}
	local in_code_block = false
	for i, line in ipairs(lines) do
		if line:match("^```%s*" .. lang .. ".*$") then
			in_code_block = true
		elseif in_code_block then
			if line:match("^```%s*$") then
				in_code_block = false
				table.insert(blocks, CodeBlock:new(i - #code_block, table.concat(code_block, " "), #code_block))
				code_block = {}
			else
				table.insert(code_block, line)
			end
		end
	end

	State.set_value("code_blocks", blocks)

	return blocks
end

---@return CodeBlock|nil The code under cursor if found, nil otherwise
CodeBlock.get_under_cursor = function()
	-- Get cursor position
	local current_window = vim.api.nvim_get_current_win()
	local cursor_row = vim.api.nvim_win_get_cursor(current_window)[1]

	local blocks = State.get_value("code_blocks")
	for _, block in pairs(blocks) do
		if cursor_row >= block.start_line - 1 and cursor_row <= block.start_line + block.num_lines then
			return block
		end
	end

	return nil
end

return CodeBlock
